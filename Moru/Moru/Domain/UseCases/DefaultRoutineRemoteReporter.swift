//
//  DefaultRoutineRemoteReporter.swift
//  Moru
//

import Foundation

@MainActor
final class DefaultRoutineRemoteReporter: RoutineRemoteReporting {
  private struct BindingKey: Hashable {
    let memberID: Int64
    let routineID: UUID
  }

  private struct Binding {
    let routineGroupID: Int64
    let localSteps: [RoutineStep]
    let remoteRoutineIDsByStepID: [UUID: Int64]

    func matches(_ routine: Routine) -> Bool {
      localSteps == routine.steps.sorted { $0.order < $1.order }
    }
  }

  private let routineRepository: any RoutineRepository
  private let routineGroupService: any AccountRoutineGroupRemoteServing
  private let executionService: any AccountRoutineExecutionRemoteServing
  private weak var signedInMemberProvider: (any SignedInMemberProviding)?
  private let fixedTimeZone: TimeZone?

  private var bindings: [BindingKey: Binding] = [:]
  private var preparationTasks: [BindingKey: Task<Binding, Error>] = [:]

  init(
    routineRepository: any RoutineRepository,
    routineGroupService: any AccountRoutineGroupRemoteServing,
    executionService: any AccountRoutineExecutionRemoteServing,
    signedInMemberProvider: any SignedInMemberProviding,
    calendar: Calendar? = nil
  ) {
    self.routineRepository = routineRepository
    self.routineGroupService = routineGroupService
    self.executionService = executionService
    self.signedInMemberProvider = signedInMemberProvider
    self.fixedTimeZone = calendar?.timeZone
  }

  func judgeCheck(
    _ request: RoutineRemoteCheckRequest
  ) async throws -> RoutineRemoteCheckResult? {
    guard
      let destination = try await destination(
        routine: request.routine,
        step: request.step
      )
    else {
      return nil
    }

    let judgment = try await executionService.judgeCheckStep(
      ServerAIExecutionSubmission(
        routineID: destination.remoteRoutineID,
        executedDate: executedDate(request.submittedAt),
        durationSeconds: boundedDuration(request.durationSeconds),
        memberInput: boundedText(request.memberInput) ?? "",
        actualWakeTime: request.actualWakeTime.map(wakeTime)
      ),
      memberID: destination.memberID
    )

    return RoutineRemoteCheckResult(
      aiResponse: judgment.aiResponse,
      shouldProceed: judgment.shouldProceed
    )
  }

  func recordExecution(
    _ request: RoutineRemoteExecutionRequest
  ) async throws {
    guard
      let destination = try await destination(
        routine: request.routine,
        step: request.step
      )
    else {
      return
    }

    _ = try await executionService.saveExecution(
      ServerRoutineExecutionSubmission(
        routineID: destination.remoteRoutineID,
        executedDate: executedDate(request.submittedAt),
        durationSeconds: boundedDuration(request.durationSeconds),
        isCompleted: request.isCompleted,
        memberInput: boundedText(request.memberInput),
        actualWakeTime: request.actualWakeTime.map(wakeTime)
      ),
      memberID: destination.memberID
    )
  }

  private func destination(
    routine: Routine,
    step: RoutineStep
  ) async throws -> (
    memberID: Int64,
    remoteRoutineID: Int64
  )? {
    guard let memberID = signedInMemberProvider?.signedInMemberID else {
      return nil
    }

    let binding = try await binding(for: routine, memberID: memberID)
    guard signedInMemberProvider?.signedInMemberID == memberID,
      let remoteRoutineID = binding.remoteRoutineIDsByStepID[step.id]
    else {
      return nil
    }

    return (memberID, remoteRoutineID)
  }

  private func binding(
    for routine: Routine,
    memberID: Int64
  ) async throws -> Binding {
    let key = BindingKey(memberID: memberID, routineID: routine.id)
    if let binding = bindings[key], binding.matches(routine) {
      return binding
    }
    bindings[key] = nil
    if let task = preparationTasks[key] {
      return try await task.value
    }

    let task = Task { @MainActor [self] in
      try await prepareBinding(for: routine, memberID: memberID)
    }
    preparationTasks[key] = task

    do {
      let binding = try await task.value
      preparationTasks[key] = nil
      bindings[key] = binding
      return binding
    } catch {
      preparationTasks[key] = nil
      throw error
    }
  }

  private func prepareBinding(
    for routine: Routine,
    memberID: Int64
  ) async throws -> Binding {
    if let routineGroupID = storedRoutineGroupID(
      remoteID: routine.sync?.remoteID,
      memberID: memberID
    ) {
      do {
        let detail = try await routineGroupService.fetchRoutineGroupDetail(
          routineGroupID: routineGroupID,
          memberID: memberID
        )
        if let binding = compatibleBinding(
          detail: detail,
          routine: routine
        ) {
          return binding
        }
      } catch APIError.server(let statusCode, _, _) where statusCode == 404 {
        // The local binding is stale. Recreate the group below.
      }
    }

    let detail = try await routineGroupService.createRoutineGroup(
      createSubmission(from: routine),
      memberID: memberID
    )
    guard
      let binding = compatibleBinding(
        detail: detail,
        routine: routine
      )
    else {
      throw AccountRoutineGroupRemoteError.invalidResponse
    }

    if var currentRoutine = try routineRepository.routine(id: routine.id) {
      var sync = currentRoutine.sync ?? .localOnly
      sync.remoteID = storedRemoteID(
        existingRemoteID: sync.remoteID,
        memberID: memberID,
        routineGroupID: binding.routineGroupID
      )
      sync.status = .localOnly
      sync.lastSyncedAt = Date()
      currentRoutine.sync = sync
      try routineRepository.saveRoutine(currentRoutine)
    }

    return binding
  }

  private func compatibleBinding(
    detail: ServerRoutineGroupDetail,
    routine: Routine
  ) -> Binding? {
    let localSteps = routine.steps.sorted { $0.order < $1.order }
    guard let remoteRoutines = detail.routines,
      remoteRoutines.count == localSteps.count
    else {
      return nil
    }

    var remoteIDsByStepID: [UUID: Int64] = [:]
    for (local, remote) in zip(localSteps, remoteRoutines) {
      guard isCompatible(local: local, remote: remote) else {
        return nil
      }
      remoteIDsByStepID[local.id] = remote.routineID
    }

    return Binding(
      routineGroupID: detail.routineGroupID,
      localSteps: localSteps,
      remoteRoutineIDsByStepID: remoteIDsByStepID
    )
  }

  private func isCompatible(
    local: RoutineStep,
    remote: ServerRoutineItem
  ) -> Bool {
    guard let remoteTitle = remote.title,
      remoteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        == local.title.trimmingCharacters(in: .whitespacesAndNewlines),
      let remoteType = remote.type,
      let remoteDurationSeconds = remote.durationSeconds,
      remoteDurationSeconds == max(local.estimatedSeconds ?? 60, 1)
    else {
      return false
    }

    switch (local.type, remoteType) {
    case (.confirm, .check), (.timer, .timer), (.input, .input):
      return true
    case (_, .unknown):
      return false
    default:
      return false
    }
  }

  private func createSubmission(
    from routine: Routine
  ) -> ServerRoutineGroupCreateSubmission {
    return ServerRoutineGroupCreateSubmission(
      title: routine.name,
      description: nilIfEmpty(routine.summary),
      alarmDaysRaw: nil,
      alarmTimeRaw: nil,
      weatherNotificationEnabled: false,
      routines: routine.steps.sorted { $0.order < $1.order }.map {
        ServerRoutineCreateSubmission(
          title: $0.title,
          type: serverType($0.type),
          durationSeconds: max($0.estimatedSeconds ?? 60, 1)
        )
      }
    )
  }

  private func serverType(_ type: RoutineStepType) -> ServerRoutineCreateType {
    switch type {
    case .confirm:
      .check
    case .timer:
      .timer
    case .input:
      .input
    }
  }

  private func executedDate(_ date: Date) -> String {
    let calendar = executionCalendar()
    let components = calendar.dateComponents(
      [.year, .month, .day],
      from: date
    )
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }

  private func wakeTime(_ date: Date) -> String {
    let calendar = executionCalendar()
    let components = calendar.dateComponents([.hour, .minute], from: date)
    return String(
      format: "%02d:%02d",
      components.hour ?? 0,
      components.minute ?? 0
    )
  }

  private func executionCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = fixedTimeZone ?? .autoupdatingCurrent
    return calendar
  }

  private func boundedDuration(_ seconds: Int?) -> Int? {
    seconds.map { min(max($0, 0), Int(Int32.max)) }
  }

  private func boundedText(_ text: String?) -> String? {
    guard let normalized = nilIfEmpty(text) else {
      return nil
    }
    return String(normalized.prefix(500))
  }

  private func nilIfEmpty(_ text: String?) -> String? {
    guard let text else {
      return nil
    }
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }

  private func storedRoutineGroupID(
    remoteID: String?,
    memberID: Int64
  ) -> Int64? {
    guard let remoteID else {
      return nil
    }
    return storedAccountBindings(remoteID)[memberID]
  }

  private func storedRemoteID(
    existingRemoteID: String?,
    memberID: Int64,
    routineGroupID: Int64
  ) -> String {
    var bindings = storedAccountBindings(existingRemoteID)
    bindings[memberID] = routineGroupID
    return bindings.sorted { $0.key < $1.key }.map { memberID, groupID in
      "\(memberID):\(groupID)"
    }.joined(separator: ";")
  }

  private func storedAccountBindings(
    _ remoteID: String?
  ) -> [Int64: Int64] {
    guard let remoteID else {
      return [:]
    }
    return remoteID.split(separator: ";").reduce(into: [:]) {
      result,
      entry in
      let components = entry.split(
        separator: ":",
        omittingEmptySubsequences: false
      )
      guard components.count == 2,
        let memberID = Int64(components[0]),
        memberID > 0,
        let routineGroupID = Int64(components[1]),
        routineGroupID > 0
      else {
        return
      }
      result[memberID] = routineGroupID
    }
  }
}
