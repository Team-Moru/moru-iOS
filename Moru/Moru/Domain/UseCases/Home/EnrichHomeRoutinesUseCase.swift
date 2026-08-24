//
//  EnrichHomeRoutinesUseCase.swift
//  Moru
//

import Foundation

@MainActor
protocol EnrichHomeRoutinesUseCaseProtocol: AnyObject {
  func execute(
    localResult: HomeRoutineLoadResult
  ) async throws -> HomeRoutineServerEnrichment
}

@MainActor
protocol HomeRoutineSyncStateReading: AnyObject {
  func binding(
    memberID: Int64,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID
  ) throws -> RoutineServerBinding?

  func hasPendingRoutineExecution(
    memberID: Int64,
    groupLocalID: UUID
  ) throws -> Bool
}

@MainActor
final class DefaultHomeRoutineSyncStateReader: HomeRoutineSyncStateReading {
  private let repository: any RoutineSyncRepository

  init(repository: any RoutineSyncRepository) {
    self.repository = repository
  }

  func binding(
    memberID: Int64,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID
  ) throws -> RoutineServerBinding? {
    try repository.binding(
      memberID: memberID,
      entityKind: entityKind,
      localEntityID: localEntityID
    )
  }

  func hasPendingRoutineExecution(
    memberID: Int64,
    groupLocalID: UUID
  ) throws -> Bool {
    try repository.mutations(memberID: memberID).contains { mutation in
      guard mutation.operation == .saveRoutineExecution else {
        return false
      }

      guard let command = try? JSONDecoder().decode(
        RoutineSyncCommand.self,
        from: mutation.payload
      ), case .saveRoutineExecution(let execution) = command else {
        // An undecodable execution row is still pending account state. It is
        // safer to retain local progress than to publish an older projection.
        return true
      }

      return execution.groupLocalID == groupLocalID
    }
  }
}

@MainActor
final class EnrichHomeRoutinesUseCase: EnrichHomeRoutinesUseCaseProtocol {
  private let remoteService: any AccountRoutineGroupRemoteServing
  private weak var sessionIdentityProvider:
    (any CurrentAccountSessionIdentityProviding)?
  private let syncStateReader: any HomeRoutineSyncStateReading
  private let localCalendar: Calendar
  private let serverCalendar: Calendar
  private let now: @Sendable () -> Date

  init(
    remoteService: any AccountRoutineGroupRemoteServing,
    sessionIdentityProvider: any CurrentAccountSessionIdentityProviding,
    syncStateReader: any HomeRoutineSyncStateReading,
    localCalendar: Calendar = .current,
    serverTimeZone: TimeZone = TimeZone(identifier: "Asia/Seoul")!,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.remoteService = remoteService
    self.sessionIdentityProvider = sessionIdentityProvider
    self.syncStateReader = syncStateReader
    var serverCalendar = Calendar(identifier: .gregorian)
    serverCalendar.timeZone = serverTimeZone
    self.localCalendar = localCalendar
    self.serverCalendar = serverCalendar
    self.now = now
  }

  func execute(
    localResult: HomeRoutineLoadResult
  ) async throws -> HomeRoutineServerEnrichment {
    try Task.checkCancellation()

    guard let capturedIdentity =
            sessionIdentityProvider?.currentAccountSessionIdentity else {
      return .fallback(.signedOut)
    }
    let requestProjection = projectionToken(at: now())
    guard requestProjection.hasMatchingDayIntervals,
          projectionToken(at: localResult.loadedAt) == requestProjection else {
      return .fallback(.serverProjectionDayMismatch)
    }

    let remoteActive: ServerActiveRoutineGroup?
    let remoteToday: ServerTodayRoutineGroupSummary?
    do {
      async let activeRequest = remoteService.fetchActiveRoutineGroup(
        identity: capturedIdentity
      )
      async let todayRequest = remoteService.fetchTodayRoutineGroupSummary(
        identity: capturedIdentity
      )
      (remoteActive, remoteToday) = try await (activeRequest, todayRequest)
    } catch is CancellationError {
      throw CancellationError()
    } catch APIError.cancelled {
      throw CancellationError()
    } catch AccountRoutineGroupRemoteError.accountAuthorizationChanged {
      throw CancellationError()
    } catch {
      guard isCurrent(capturedIdentity) else {
        throw CancellationError()
      }
      return .fallback(.remoteUnavailable)
    }

    try Task.checkCancellation()
    guard isCurrent(capturedIdentity) else {
      throw CancellationError()
    }
    guard projectionToken(at: now()) == requestProjection else {
      return .fallback(.serverProjectionDayMismatch)
    }

    return makeEnrichment(
      active: remoteActive,
      today: remoteToday,
      localResult: localResult,
      memberID: capturedIdentity.memberID
    )
  }

  private func makeEnrichment(
    active: ServerActiveRoutineGroup?,
    today: ServerTodayRoutineGroupSummary?,
    localResult: HomeRoutineLoadResult,
    memberID: Int64
  ) -> HomeRoutineServerEnrichment {
    switch (active, today) {
    case (nil, nil):
      return localResult.manualRoutines.isEmpty
        ? .noActive
        : .fallback(.remoteHasNoActiveLocalHasActive)
    case (nil, _), (_, nil):
      return .fallback(.inconsistentRemoteSnapshot)
    case (.some(let active), .some(let today)):
      return bind(
        active: active,
        today: today,
        localResult: localResult,
        memberID: memberID
      )
    }
  }

  private func bind(
    active: ServerActiveRoutineGroup,
    today: ServerTodayRoutineGroupSummary,
    localResult: HomeRoutineLoadResult,
    memberID: Int64
  ) -> HomeRoutineServerEnrichment {
    guard !localResult.manualRoutines.isEmpty else {
      return .fallback(.localActiveMissing)
    }
    guard localResult.manualRoutines.count == 1,
          let localRoutine = localResult.manualRoutines.first else {
      return .fallback(.localActiveAmbiguous)
    }

    let groupBinding: RoutineServerBinding
    do {
      guard let binding = try syncStateReader.binding(
        memberID: memberID,
        entityKind: .routineGroup,
        localEntityID: localRoutine.id
      ) else {
        return .fallback(.activeGroupBindingMissing)
      }
      groupBinding = binding
    } catch {
      return .fallback(.localSyncStateUnavailable)
    }

    guard groupBinding.serverNamespace == .production,
          groupBinding.memberID == memberID,
          groupBinding.entityKind == .routineGroup,
          groupBinding.localEntityID == localRoutine.id,
          groupBinding.remoteID == active.routineGroupID else {
      return .fallback(.activeGroupIdentityMismatch)
    }

    guard today.totalCount == active.routines.count,
          today.completedCount == active.routines.filter(\.isCompleted).count,
          today.completionRate == active.completionRate,
          hasCoherentProgress(
            completed: today.completedCount,
            total: today.totalCount,
            rate: today.completionRate
          ) else {
      return .fallback(.inconsistentRemoteSnapshot)
    }

    let serverRoutineIDs = Set(active.routines.map(\.routineID))
    guard serverRoutineIDs.count == localRoutine.steps.count else {
      return .fallback(.activeRoutineIdentityMismatch)
    }

    var localStepIDByServerID: [Int64: UUID] = [:]
    do {
      for step in localRoutine.steps {
        guard let binding = try syncStateReader.binding(
          memberID: memberID,
          entityKind: .routine,
          localEntityID: step.id
        ) else {
          return .fallback(.activeRoutineBindingMissing)
        }
        guard binding.serverNamespace == .production,
              binding.memberID == memberID,
              binding.entityKind == .routine,
              binding.localEntityID == step.id,
              binding.parentEntityKind == .routineGroup,
              binding.parentLocalEntityID == localRoutine.id,
              serverRoutineIDs.contains(binding.remoteID),
              localStepIDByServerID.updateValue(
                step.id,
                forKey: binding.remoteID
              ) == nil else {
          return .fallback(.activeRoutineIdentityMismatch)
        }
      }
    } catch {
      return .fallback(.localSyncStateUnavailable)
    }

    guard Set(localStepIDByServerID.keys) == serverRoutineIDs else {
      return .fallback(.activeRoutineIdentityMismatch)
    }

    let boundRoutines: [HomeBoundRoutineProgress]
    do {
      boundRoutines = try active.routines.map { routine in
        guard let localStepID = localStepIDByServerID[routine.routineID] else {
          throw HomeRoutineBindingError.missingRoutine
        }
        return HomeBoundRoutineProgress(
          localStepID: localStepID,
          isCompleted: routine.isCompleted,
          completedTimeSeconds: routine.completedTimeSeconds
        )
      }
    } catch {
      return .fallback(.activeRoutineIdentityMismatch)
    }

    do {
      guard try !syncStateReader.hasPendingRoutineExecution(
        memberID: memberID,
        groupLocalID: localRoutine.id
      ) else {
        return .fallback(.pendingLocalExecution)
      }
    } catch {
      return .fallback(.localSyncStateUnavailable)
    }

    return .applied(
      HomeBoundActiveRoutineSnapshot(
        localRoutineID: localRoutine.id,
        completionRate: active.completionRate,
        routines: boundRoutines,
        today: HomeBoundTodayProgress(
          completedCount: today.completedCount,
          totalCount: today.totalCount,
          completionRate: today.completionRate
        )
      )
    )
  }

  private func isCurrent(_ identity: AccountSessionIdentity) -> Bool {
    sessionIdentityProvider?.currentAccountSessionIdentity == identity
  }

  private func hasCoherentProgress(
    completed: Int,
    total: Int,
    rate: Double
  ) -> Bool {
    let expectedPercentage = total == 0
      ? 0
      : Int((Double(completed) * 100 / Double(total)).rounded())
    return rate == Double(expectedPercentage) / 100
  }

  private func projectionToken(at date: Date) -> HomeProjectionToken {
    return HomeProjectionToken(
      localDay: localCalendar.dateInterval(of: .day, for: date),
      serverDay: serverCalendar.dateInterval(of: .day, for: date)
    )
  }
}

nonisolated private enum HomeRoutineBindingError: Error {
  case missingRoutine
}

nonisolated private struct HomeProjectionToken: Equatable {
  let localDay: DateInterval?
  let serverDay: DateInterval?

  var hasMatchingDayIntervals: Bool {
    guard let localDay, let serverDay else {
      return false
    }
    return localDay == serverDay
  }
}
