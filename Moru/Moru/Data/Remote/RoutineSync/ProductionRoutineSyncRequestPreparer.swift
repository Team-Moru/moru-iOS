//
//  ProductionRoutineSyncRequestPreparer.swift
//  Moru
//

import Foundation

nonisolated enum RoutineSyncRequestPreparingError:
  Error,
  Equatable,
  Sendable {
  case unsupportedOperation
  case commandDoesNotMatchMutation
  case invalidLocalSnapshot
  case missingServerBinding
  case conflictingServerBinding
}

/// Converts one immutable Outbox command into the exact production HTTP
/// artifact that is persisted with its first attempt. This type is only used
/// for the first send; exact replay reads the persisted artifact instead.
@MainActor
final class ProductionRoutineSyncRequestPreparer:
  RoutineSyncWireRequestPreparing {
  private let repository: any RoutineSyncRepository
  private let encoder: JSONEncoder

  init(repository: any RoutineSyncRepository) {
    self.repository = repository
    encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  }

  func makeWireRequest(
    for command: RoutineSyncCommand,
    mutation: RoutineSyncMutation
  ) throws -> RoutineSyncWireRequest {
    guard mutation.serverNamespace == .production,
          mutation.memberID > 0,
          command.operation == mutation.operation,
          command.entityKind == mutation.entityKind,
          command.localEntityID == mutation.localEntityID else {
      throw RoutineSyncRequestPreparingError.commandDoesNotMatchMutation
    }

    switch command {
    case .createRoutineGroup(let group):
      return try makeCreateGroupRequest(
        group,
        memberID: mutation.memberID
      )

    case .addRoutine(let groupLocalID, let routine):
      return try makeAddRoutineRequest(
        groupLocalID: groupLocalID,
        routine: routine,
        memberID: mutation.memberID
      )

    case .deleteRoutineGroup(let groupLocalID):
      return try makeDeleteGroupRequest(
        groupLocalID: groupLocalID,
        memberID: mutation.memberID
      )

    case .deleteRoutine(let groupLocalID, let routineLocalID):
      return try makeDeleteRoutineRequest(
        groupLocalID: groupLocalID,
        routineLocalID: routineLocalID,
        memberID: mutation.memberID
      )

    case .saveRoutineExecution(let execution):
      return try makeExecutionRequest(
        execution,
        memberID: mutation.memberID
      )

    case .completeOnboarding(let groupLocalID):
      return try makeOnboardingCompletionRequest(
        groupLocalID: groupLocalID,
        memberID: mutation.memberID
      )

    case .selectActiveRoutineGroup(let selectedGroupLocalID):
      return try makeSelectActiveRoutineGroupRequest(
        selectedGroupLocalID: selectedGroupLocalID,
        memberID: mutation.memberID
      )
    }
  }

  private func makeOnboardingCompletionRequest(
    groupLocalID: UUID,
    memberID: Int64
  ) throws -> RoutineSyncWireRequest {
    let groupBinding = try requiredBinding(
      memberID: memberID,
      entityKind: .routineGroup,
      localEntityID: groupLocalID
    )
    guard groupBinding.parentEntityKind == nil,
          groupBinding.parentLocalEntityID == nil else {
      throw RoutineSyncRequestPreparingError.conflictingServerBinding
    }
    return RoutineSyncWireRequest(
      method: .post,
      path: "/onboarding/complete",
      body: try encoded(
        ProductionOnboardingCompletionRequestDTO(
          routineGroupId: groupBinding.remoteID
        )
      )
    )
  }

  private func makeExecutionRequest(
    _ execution: RoutineSyncExecutionSnapshot,
    memberID: Int64
  ) throws -> RoutineSyncWireRequest {
    guard execution.runLocalID != execution.result.localID,
          execution.groupLocalID != execution.routineLocalID,
          execution.routineLocalID != execution.result.localID,
          execution.runCompletedAt != nil,
          execution.result.completedAt != nil || execution.result.skipped,
          TimeZone(identifier: execution.timeZoneIdentifier) != nil,
          try repository.binding(
            memberID: memberID,
            entityKind: .routineExecution,
            localEntityID: execution.result.localID
          ) == nil else {
      throw RoutineSyncRequestPreparingError.invalidLocalSnapshot
    }
    let groupBinding = try requiredBinding(
      memberID: memberID,
      entityKind: .routineGroup,
      localEntityID: execution.groupLocalID
    )
    let routineBinding = try requiredBinding(
      memberID: memberID,
      entityKind: .routine,
      localEntityID: execution.routineLocalID
    )
    guard routineBinding.parentEntityKind == .routineGroup,
          routineBinding.parentLocalEntityID == execution.groupLocalID,
          routineBinding.remoteID != groupBinding.remoteID else {
      throw RoutineSyncRequestPreparingError.conflictingServerBinding
    }

    let duration: Int?
    if let value = execution.result.durationSeconds {
      guard (0...Int(Int32.max)).contains(value) else {
        throw RoutineSyncRequestPreparingError.invalidLocalSnapshot
      }
      duration = value
    } else {
      duration = nil
    }
    let memberInput = execution.result.inputText
      ?? execution.result.transcript
    guard memberInput?.utf16.count ?? 0 <= 500 else {
      throw RoutineSyncRequestPreparingError.invalidLocalSnapshot
    }
    let executedDate = try localDateString(
      execution.runStartedAt,
      timeZoneIdentifier: execution.timeZoneIdentifier
    )
    let request = ProductionRoutineExecutionRequestDTO(
      executedDate: executedDate,
      routineId: routineBinding.remoteID,
      durationSecond: duration,
      memberInput: memberInput,
      aiResponse: nil,
      isCompleted: !execution.result.skipped
        && execution.result.completedAt != nil,
      actualWakeTime: nil
    )
    return RoutineSyncWireRequest(
      method: .post,
      path: "/routine-executions",
      body: try encoded(request)
    )
  }

  private func makeCreateGroupRequest(
    _ group: RoutineSyncGroupSnapshot,
    memberID: Int64
  ) throws -> RoutineSyncWireRequest {
    guard try repository.binding(
      memberID: memberID,
      entityKind: .routineGroup,
      localEntityID: group.localID
    ) == nil,
    !group.routines.isEmpty else {
      throw RoutineSyncRequestPreparingError.conflictingServerBinding
    }

    let localIDs = [group.localID] + group.routines.map(\.localID)
    guard Set(localIDs).count == localIDs.count else {
      throw RoutineSyncRequestPreparingError.invalidLocalSnapshot
    }
    for routine in group.routines {
      guard try repository.binding(
        memberID: memberID,
        entityKind: .routine,
        localEntityID: routine.localID
      ) == nil else {
        throw RoutineSyncRequestPreparingError.conflictingServerBinding
      }
    }

    let schedule = try makeSchedule(for: group)
    let request = ProductionRoutineGroupCreateRequestDTO(
      title: try nonempty(group.name),
      description: normalized(group.summary),
      alarmDays: schedule?.days,
      alarmTime: schedule?.time,
      weatherNotificationEnabled: schedule?.includeWeather ?? false,
      routines: try group.routines.map(makeRoutineRequest),
      clientEntityId: canonical(group.localID)
    )
    return RoutineSyncWireRequest(
      method: .post,
      path: "/routine-groups",
      body: try encoded(request)
    )
  }

  private func makeAddRoutineRequest(
    groupLocalID: UUID,
    routine: RoutineSyncRoutineSnapshot,
    memberID: Int64
  ) throws -> RoutineSyncWireRequest {
    guard groupLocalID != routine.localID else {
      throw RoutineSyncRequestPreparingError.invalidLocalSnapshot
    }
    let groupBinding = try requiredBinding(
      memberID: memberID,
      entityKind: .routineGroup,
      localEntityID: groupLocalID
    )
    guard groupBinding.parentEntityKind == nil,
          groupBinding.parentLocalEntityID == nil,
          try repository.binding(
            memberID: memberID,
            entityKind: .routine,
            localEntityID: routine.localID
          ) == nil else {
      throw RoutineSyncRequestPreparingError.conflictingServerBinding
    }

    return RoutineSyncWireRequest(
      method: .post,
      path: "/routine-groups/\(groupBinding.remoteID)/routines",
      body: try encoded(makeRoutineRequest(routine))
    )
  }

  private func makeDeleteGroupRequest(
    groupLocalID: UUID,
    memberID: Int64
  ) throws -> RoutineSyncWireRequest {
    let binding = try requiredBinding(
      memberID: memberID,
      entityKind: .routineGroup,
      localEntityID: groupLocalID
    )
    guard binding.parentEntityKind == nil,
          binding.parentLocalEntityID == nil else {
      throw RoutineSyncRequestPreparingError.conflictingServerBinding
    }
    return RoutineSyncWireRequest(
      method: .delete,
      path: "/routine-groups/\(binding.remoteID)",
      body: Data()
    )
  }

  /// Deactivating with no replacement (`selectedGroupLocalID == nil`) has no
  /// local record of which remote group was previously active, so it cannot
  /// yet be turned into a `PATCH .../active` call. It remains unsupported
  /// until that local tracking exists; the queued mutation stays blocked
  /// rather than silently no-op-ing.
  private func makeSelectActiveRoutineGroupRequest(
    selectedGroupLocalID: UUID?,
    memberID: Int64
  ) throws -> RoutineSyncWireRequest {
    guard let selectedGroupLocalID else {
      throw RoutineSyncRequestPreparingError.unsupportedOperation
    }
    let binding = try requiredBinding(
      memberID: memberID,
      entityKind: .routineGroup,
      localEntityID: selectedGroupLocalID
    )
    guard binding.parentEntityKind == nil,
          binding.parentLocalEntityID == nil else {
      throw RoutineSyncRequestPreparingError.conflictingServerBinding
    }
    return RoutineSyncWireRequest(
      method: .patch,
      path: "/routine-groups/\(binding.remoteID)/active",
      body: try encoded(ProductionRoutineGroupActiveRequestDTO(isActive: true))
    )
  }

  private func makeDeleteRoutineRequest(
    groupLocalID: UUID?,
    routineLocalID: UUID,
    memberID: Int64
  ) throws -> RoutineSyncWireRequest {
    guard let groupLocalID,
          groupLocalID != routineLocalID else {
      throw RoutineSyncRequestPreparingError.missingServerBinding
    }
    let groupBinding = try requiredBinding(
      memberID: memberID,
      entityKind: .routineGroup,
      localEntityID: groupLocalID
    )
    let routineBinding = try requiredBinding(
      memberID: memberID,
      entityKind: .routine,
      localEntityID: routineLocalID
    )
    guard routineBinding.parentEntityKind == .routineGroup,
          routineBinding.parentLocalEntityID == groupLocalID,
          routineBinding.remoteID != groupBinding.remoteID else {
      throw RoutineSyncRequestPreparingError.conflictingServerBinding
    }

    return RoutineSyncWireRequest(
      method: .delete,
      path: "/routines/\(routineBinding.remoteID)",
      body: Data()
    )
  }

  private func requiredBinding(
    memberID: Int64,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID
  ) throws -> RoutineServerBinding {
    guard let binding = try repository.binding(
      memberID: memberID,
      entityKind: entityKind,
      localEntityID: localEntityID
    ), binding.remoteID > 0 else {
      throw RoutineSyncRequestPreparingError.missingServerBinding
    }
    return binding
  }

  private func makeRoutineRequest(
    _ routine: RoutineSyncRoutineSnapshot
  ) throws -> ProductionRoutineRequestDTO {
    let type: String
    switch routine.type {
    case RoutineStepType.confirm.rawValue:
      type = "CHECK"
    case RoutineStepType.timer.rawValue:
      type = "TIMER"
    case RoutineStepType.input.rawValue:
      type = "INPUT"
    default:
      throw RoutineSyncRequestPreparingError.invalidLocalSnapshot
    }

    let duration: Int
    if let durationSeconds = routine.durationSeconds {
      guard (0...Int(Int32.max)).contains(durationSeconds) else {
        throw RoutineSyncRequestPreparingError.invalidLocalSnapshot
      }
      duration = durationSeconds
    } else if type == "TIMER" {
      throw RoutineSyncRequestPreparingError.invalidLocalSnapshot
    } else {
      duration = 0
    }

    return ProductionRoutineRequestDTO(
      title: try nonempty(routine.title),
      type: type,
      durationSecond: duration,
      clientEntityId: canonical(routine.localID)
    )
  }

  private func makeSchedule(
    for group: RoutineSyncGroupSnapshot
  ) throws -> ProductionRoutineAlarmDTO? {
    guard group.isActive,
          let alarm = group.alarm,
          alarm.isEnabled else {
      return nil
    }
    guard (0...23).contains(alarm.hour),
          (0...59).contains(alarm.minute),
          !alarm.weekdays.isEmpty,
          alarm.weekdays.allSatisfy({ (1...7).contains($0) }) else {
      throw RoutineSyncRequestPreparingError.invalidLocalSnapshot
    }

    let names: [Int: String] = [
      2: "MON",
      3: "TUE",
      4: "WED",
      5: "THU",
      6: "FRI",
      7: "SAT",
      1: "SUN",
    ]
    let canonicalOrder = [2, 3, 4, 5, 6, 7, 1]
    let selectedDays = Set(alarm.weekdays)
    let days = canonicalOrder.compactMap { day in
      selectedDays.contains(day) ? names[day] : nil
    }
    guard !days.isEmpty else {
      throw RoutineSyncRequestPreparingError.invalidLocalSnapshot
    }
    return ProductionRoutineAlarmDTO(
      days: days.joined(separator: ","),
      time: String(format: "%02d:%02d", alarm.hour, alarm.minute),
      includeWeather: alarm.includeWeather
    )
  }

  private func encoded<Payload: Encodable>(_ payload: Payload) throws -> Data {
    do {
      return try encoder.encode(payload)
    } catch {
      throw RoutineSyncRequestPreparingError.invalidLocalSnapshot
    }
  }

  private func nonempty(_ value: String) throws -> String {
    guard let normalized = normalized(value) else {
      throw RoutineSyncRequestPreparingError.invalidLocalSnapshot
    }
    return normalized
  }

  private func normalized(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func canonical(_ id: UUID) -> String {
    id.uuidString.lowercased()
  }

  private func localDateString(
    _ date: Date,
    timeZoneIdentifier: String
  ) throws -> String {
    guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
      throw RoutineSyncRequestPreparingError.invalidLocalSnapshot
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = components.year,
          let month = components.month,
          let day = components.day else {
      throw RoutineSyncRequestPreparingError.invalidLocalSnapshot
    }
    return String(format: "%04d-%02d-%02d", year, month, day)
  }
}

nonisolated private struct ProductionRoutineGroupCreateRequestDTO: Encodable {
  let title: String
  let description: String?
  let alarmDays: String?
  let alarmTime: String?
  let weatherNotificationEnabled: Bool
  let routines: [ProductionRoutineRequestDTO]
  let clientEntityId: String
}

nonisolated private struct ProductionRoutineRequestDTO: Encodable {
  let title: String
  let type: String
  let durationSecond: Int
  let clientEntityId: String
}

nonisolated private struct ProductionRoutineAlarmDTO {
  let days: String
  let time: String
  let includeWeather: Bool
}

nonisolated private struct ProductionRoutineExecutionRequestDTO: Encodable {
  let executedDate: String
  let routineId: Int64
  let durationSecond: Int?
  let memberInput: String?
  let aiResponse: String?
  let isCompleted: Bool
  let actualWakeTime: String?
}

nonisolated private struct ProductionRoutineGroupActiveRequestDTO: Encodable {
  let isActive: Bool
}

nonisolated private struct ProductionOnboardingCompletionRequestDTO: Encodable {
  let routineGroupId: Int64
}
