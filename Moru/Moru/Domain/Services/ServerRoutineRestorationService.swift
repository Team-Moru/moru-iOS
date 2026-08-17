//
//  ServerRoutineRestorationService.swift
//  Moru
//

import Foundation

@MainActor
protocol ServerRoutineRestorationPersisting: AnyObject {
  func localDataState() throws -> ServerRoutineRestorationLocalDataState

  /// Returns `false` when local data appeared while remote reads were in
  /// flight. Implementations must persist the profile, routines, and bindings
  /// in one transaction.
  func persistServerRestoration(
    _ snapshot: ServerRoutineRestorationSnapshot,
    memberID: Int64,
    replacing source: ServerRoutineRestorationSource,
    at date: Date
  ) throws -> Bool

  func finalizeProvisionalDataAsEstablished(
    generationID: UUID
  ) throws -> Bool
}

@MainActor
protocol ServerRoutineRestoring: AnyObject {
  func localDataState() throws -> ServerRoutineRestorationLocalDataState

  func restore(
    for identity: AccountSessionIdentity,
    replacing source: ServerRoutineRestorationSource
  ) async throws -> ServerRoutineRestorationResult

  func finalizeLocalDataForBackfill(
    for identity: AccountSessionIdentity,
    source: ServerRoutineRestorationSource
  ) throws
}

nonisolated enum ServerRoutineRestorationResult: Equatable, Sendable {
  case restored(routineCount: Int)
  case localDataPresent
}

nonisolated enum ServerRoutineRestorationError:
  Error,
  Equatable,
  Sendable {
  case invalidResponse
  case localDataChanged
  case staleSession
}

@MainActor
struct ServerRoutineRestorationSnapshot {
  let profile: LocalProfile
  let routines: [Routine]
  let bindingAssignments: [RoutineServerBindingAssignment]
}

/// Restores only the server projection that has a direct local equivalent.
///
/// Server routine-group nested `steps` have no local persistence layer: one
/// server routine is already one local `RoutineStep`. Their IDs and contents
/// are therefore deliberately not synthesized into local user data.
@MainActor
final class DefaultServerRoutineRestorationService:
  ServerRoutineRestoring {
  private let remoteService: any AccountRoutineGroupRemoteServing
  private let persistence: any ServerRoutineRestorationPersisting
  private weak var sessionIdentityProvider:
    (any CurrentAccountSessionIdentityProviding)?
  private let now: () -> Date

  init(
    remoteService: any AccountRoutineGroupRemoteServing,
    persistence: any ServerRoutineRestorationPersisting,
    sessionIdentityProvider:
      any CurrentAccountSessionIdentityProviding,
    now: @escaping () -> Date = Date.init
  ) {
    self.remoteService = remoteService
    self.persistence = persistence
    self.sessionIdentityProvider = sessionIdentityProvider
    self.now = now
  }

  func localDataState() throws -> ServerRoutineRestorationLocalDataState {
    try persistence.localDataState()
  }

  func restore(
    for identity: AccountSessionIdentity,
    replacing source: ServerRoutineRestorationSource
  ) async throws -> ServerRoutineRestorationResult {
    guard try persistence.localDataState().restorationSource == source else {
      return try resultForChangedLocalData()
    }
    try requireCurrent(identity)

    let summaries = try await remoteService.fetchRoutineGroups(
      memberID: identity.memberID
    )
    try Task.checkCancellation()
    try requireCurrent(identity)

    var details: [ServerRoutineGroupDetail] = []
    details.reserveCapacity(summaries.count)
    for summary in summaries {
      let detail = try await remoteService.fetchRoutineGroupDetail(
        routineGroupID: summary.routineGroupID,
        memberID: identity.memberID
      )
      try Task.checkCancellation()
      try requireCurrent(identity)
      details.append(detail)
    }

    let restorationDate = now()
    let snapshot = try ServerRoutineRestorationMapper.makeSnapshot(
      summaries: summaries,
      details: details,
      at: restorationDate
    )
    try Task.checkCancellation()
    try requireCurrent(identity)

    let didPersist = try persistence.persistServerRestoration(
      snapshot,
      memberID: identity.memberID,
      replacing: source,
      at: restorationDate
    )
    guard didPersist else {
      return try resultForChangedLocalData()
    }
    return .restored(routineCount: snapshot.routines.count)
  }

  func finalizeLocalDataForBackfill(
    for identity: AccountSessionIdentity,
    source: ServerRoutineRestorationSource
  ) throws {
    try requireCurrent(identity)
    guard case .provisional(let generationID) = source else {
      return
    }
    guard try persistence.finalizeProvisionalDataAsEstablished(
      generationID: generationID
    ) else {
      throw ServerRoutineRestorationError.localDataChanged
    }
    try requireCurrent(identity)
  }

  private func requireCurrent(
    _ identity: AccountSessionIdentity
  ) throws {
    guard sessionIdentityProvider?.currentAccountSessionIdentity
      == identity else {
      throw ServerRoutineRestorationError.staleSession
    }
  }

  private func resultForChangedLocalData()
    throws -> ServerRoutineRestorationResult {
    guard try persistence.localDataState() == .established else {
      throw ServerRoutineRestorationError.localDataChanged
    }
    return .localDataPresent
  }
}

@MainActor
enum ServerRoutineRestorationMapper {
  static func makeSnapshot(
    summaries: [ServerRoutineGroupSummary],
    details: [ServerRoutineGroupDetail],
    at date: Date
  ) throws -> ServerRoutineRestorationSnapshot {
    guard summaries.count == details.count else {
      throw ServerRoutineRestorationError.invalidResponse
    }

    var detailsByGroupID: [Int64: ServerRoutineGroupDetail] = [:]
    for detail in details {
      guard detailsByGroupID.updateValue(
        detail,
        forKey: detail.routineGroupID
      ) == nil else {
        throw ServerRoutineRestorationError.invalidResponse
      }
    }

    var routines: [Routine] = []
    var assignments: [RoutineServerBindingAssignment] = []
    var activeGroupCount = 0

    for summary in summaries {
      guard let detail = detailsByGroupID.removeValue(
              forKey: summary.routineGroupID
            ),
            let isActive = summary.isActive,
            let serverRoutineItems = detail.routines,
            let name = detail.title ?? summary.title else {
        throw ServerRoutineRestorationError.invalidResponse
      }

      activeGroupCount += isActive ? 1 : 0
      guard activeGroupCount <= 1 else {
        throw ServerRoutineRestorationError.invalidResponse
      }

      let localGroupID = UUID()
      let localSteps = try serverRoutineItems.enumerated().map {
        index,
        item in
        try makeStep(from: item, order: index)
      }
      let routine = Routine(
        id: localGroupID,
        name: name,
        summary: detail.description ?? "",
        goalTags: [],
        steps: localSteps,
        alarmSchedule: try makeAlarmSchedule(
          from: detail,
          isActive: isActive
        ),
        isActive: isActive,
        createdAt: date,
        updatedAt: date,
        sync: .localOnly
      )
      routines.append(routine)

      assignments.append(
        RoutineServerBindingAssignment(
          entityKind: .routineGroup,
          localEntityID: localGroupID,
          remoteID: summary.routineGroupID
        )
      )
      assignments.append(
        contentsOf: zip(localSteps, serverRoutineItems).map {
          localStep,
          serverItem in
          RoutineServerBindingAssignment(
            entityKind: .routine,
            localEntityID: localStep.id,
            remoteID: serverItem.routineID,
            parentEntityKind: .routineGroup,
            parentLocalEntityID: localGroupID
          )
        }
      )
    }

    guard detailsByGroupID.isEmpty else {
      throw ServerRoutineRestorationError.invalidResponse
    }

    return ServerRoutineRestorationSnapshot(
      profile: LocalProfile(createdAt: date, updatedAt: date),
      routines: routines,
      bindingAssignments: assignments
    )
  }

  private static func makeStep(
    from item: ServerRoutineItem,
    order: Int
  ) throws -> RoutineStep {
    guard let title = item.title,
          let serverType = item.type else {
      throw ServerRoutineRestorationError.invalidResponse
    }

    let type: RoutineStepType
    switch serverType {
    case .check:
      type = .confirm
    case .timer:
      type = .timer
    case .input:
      type = .input
    case .unknown:
      throw ServerRoutineRestorationError.invalidResponse
    }

    let estimatedSeconds: Int?
    if type == .timer {
      guard let durationSeconds = item.durationSeconds,
            durationSeconds > 0 else {
        throw ServerRoutineRestorationError.invalidResponse
      }
      estimatedSeconds = durationSeconds
    } else if let durationSeconds = item.durationSeconds,
              durationSeconds > 0 {
      estimatedSeconds = durationSeconds
    } else {
      // The current create API represents a missing non-timer duration as 0.
      estimatedSeconds = nil
    }

    return RoutineStep(
      id: UUID(),
      presetItemID: nil,
      type: type,
      title: title,
      instruction: "",
      order: order,
      estimatedSeconds: estimatedSeconds,
      isRequired: true
    )
  }

  private static func makeAlarmSchedule(
    from detail: ServerRoutineGroupDetail,
    isActive: Bool
  ) throws -> AlarmSchedule? {
    switch (detail.alarmDaysRaw, detail.alarmTimeRaw) {
    case (nil, nil):
      return nil
    case (.some(let rawDays), .some(let rawTime)):
      let time = try alarmTime(rawTime)
      return AlarmSchedule(
        id: UUID(),
        hour: time.hour,
        minute: time.minute,
        weekdays: try weekdays(rawDays),
        soundName: "moru-default",
        isEnabled: isActive,
        includeWeather: detail.weatherNotificationEnabled ?? false,
        includeFortune: false
      )
    case (.some, nil), (nil, .some):
      throw ServerRoutineRestorationError.invalidResponse
    }
  }

  private static func weekdays(_ rawValue: String) throws -> [Weekday] {
    let names: [String: Weekday] = [
      "MON": .monday,
      "TUE": .tuesday,
      "WED": .wednesday,
      "THU": .thursday,
      "FRI": .friday,
      "SAT": .saturday,
      "SUN": .sunday,
    ]
    let components = rawValue.components(separatedBy: ",").map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard !components.isEmpty,
          components.allSatisfy({ !$0.isEmpty }),
          Set(components).count == components.count else {
      throw ServerRoutineRestorationError.invalidResponse
    }

    let values = try components.map { component in
      guard let weekday = names[component] else {
        throw ServerRoutineRestorationError.invalidResponse
      }
      return weekday
    }
    return values.sortedByDisplayOrder()
  }

  private static func alarmTime(
    _ rawValue: String
  ) throws -> (hour: Int, minute: Int) {
    let components = rawValue.split(
      separator: ":",
      omittingEmptySubsequences: false
    )
    guard components.count == 2,
          components[0].count == 2,
          components[1].count == 2,
          let hour = Int(components[0]),
          let minute = Int(components[1]),
          (0...23).contains(hour),
          (0...59).contains(minute) else {
      throw ServerRoutineRestorationError.invalidResponse
    }
    return (hour, minute)
  }
}
