//
//  RemoteRoutineGroupService.swift
//  Moru
//

import Foundation

nonisolated final class DefaultAccountRoutineGroupRemoteService:
  AccountRoutineGroupRemoteServing {
  private static let noActiveRoutineCode = "ROUTINE4005"

  private let apiClient: any AccountBoundAPIClient

  init(apiClient: any AccountBoundAPIClient) {
    self.apiClient = apiClient
  }

  func fetchRoutineGroups(
    memberID: Int64
  ) async throws -> [ServerRoutineGroupSummary] {
    guard memberID > 0 else {
      throw AccountRoutineGroupRemoteError.invalidRequest
    }

    return try await performAccountRequest {
      let response = try await apiClient.request(
        RoutineGroupTarget.list,
        as: [RoutineGroupSummaryResponseDTO].self,
        authorizedForMemberID: memberID
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try response.makeDomainModels()
    }
  }

  func fetchRoutineGroupDetail(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> ServerRoutineGroupDetail {
    guard memberID > 0, routineGroupID > 0 else {
      throw AccountRoutineGroupRemoteError.invalidRequest
    }

    return try await performAccountRequest {
      let response = try await apiClient.request(
        RoutineGroupTarget.detail(routineGroupID: routineGroupID),
        as: RoutineGroupDetailResponseDTO.self,
        authorizedForMemberID: memberID
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try response.makeDomainModel(
        expectedRoutineGroupID: routineGroupID
      )
    }
  }

  func fetchActiveRoutineGroup(
    memberID: Int64
  ) async throws -> ServerActiveRoutineGroup? {
    guard memberID > 0 else {
      throw AccountRoutineGroupRemoteError.invalidRequest
    }

    return try await performOptionalActiveRoutineRequest {
      let response = try await apiClient.request(
        RoutineGroupTarget.active,
        as: ActiveRoutineGroupResponseDTO.self,
        authorizedForMemberID: memberID
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try response.makeDomainModel()
    }
  }

  func fetchTodayRoutineProgress(
    memberID: Int64
  ) async throws -> ServerTodayRoutineProgress? {
    guard memberID > 0 else {
      throw AccountRoutineGroupRemoteError.invalidRequest
    }

    return try await performOptionalActiveRoutineRequest {
      let response = try await apiClient.request(
        RoutineGroupTarget.today,
        as: TodayRoutineProgressResponseDTO.self,
        authorizedForMemberID: memberID
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try response.makeDomainModel()
    }
  }

  func updateRoutineGroupActivation(
    routineGroupID: Int64,
    isActive: Bool,
    memberID: Int64
  ) async throws -> ServerRoutineGroupActivation {
    guard memberID > 0, routineGroupID > 0 else {
      throw AccountRoutineGroupRemoteError.invalidRequest
    }

    return try await performAccountRequest {
      let response = try await apiClient.request(
        RoutineGroupTarget.updateActivation(
          routineGroupID: routineGroupID,
          request: RoutineGroupActivationRequestDTO(
            isActive: isActive
          )
        ),
        as: RoutineGroupActivationResponseDTO.self,
        authorizedForMemberID: memberID
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try response.makeDomainModel(
        expectedRoutineGroupID: routineGroupID,
        expectedIsActive: isActive
      )
    }
  }

  private func performOptionalActiveRoutineRequest<Output: Sendable>(
    _ operation: () async throws -> Output
  ) async throws -> Output? {
    do {
      return try await performAccountRequest(operation)
    } catch APIError.server(let statusCode, let code, _)
      where statusCode == 404 && code == Self.noActiveRoutineCode {
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return nil
    }
  }

  private func performAccountRequest<Output: Sendable>(
    _ operation: () async throws -> Output
  ) async throws -> Output {
    do {
      return try await operation()
    } catch is CancellationError {
      throw CancellationError()
    } catch APIError.cancelled {
      throw CancellationError()
    } catch is AccountAuthorizationContextError {
      throw AccountRoutineGroupRemoteError.accountAuthorizationChanged
    }
  }
}

nonisolated private extension Array
where Element == RoutineGroupSummaryResponseDTO {
  func makeDomainModels() throws -> [ServerRoutineGroupSummary] {
    var seenRoutineGroupIDs: Set<Int64> = []

    return try map { summary in
      try _Concurrency.Task<Never, Never>.checkCancellation()
      guard let routineGroupID = summary.routineGroupId,
            routineGroupID > 0,
            seenRoutineGroupIDs.insert(routineGroupID).inserted else {
        throw AccountRoutineGroupRemoteError.invalidResponse
      }

      return ServerRoutineGroupSummary(
        routineGroupID: routineGroupID,
        title: try normalizedRoutineGroupText(summary.title),
        isActive: summary.isActive,
        routineCount: try validatedOptionalInt32Value(
          summary.routineCount
        ),
        totalDurationSeconds: try validatedOptionalInt32Value(
          summary.totalDurationSecond
        )
      )
    }
  }
}

nonisolated private extension RoutineGroupDetailResponseDTO {
  func makeDomainModel(
    expectedRoutineGroupID: Int64
  ) throws -> ServerRoutineGroupDetail {
    guard let routineGroupID = routineGroupId,
          routineGroupID > 0,
          routineGroupID == expectedRoutineGroupID else {
      throw AccountRoutineGroupRemoteError.invalidResponse
    }

    return ServerRoutineGroupDetail(
      routineGroupID: routineGroupID,
      title: try normalizedRoutineGroupText(title),
      description: try normalizedRoutineGroupText(description),
      alarmDaysRaw: try normalizedRoutineGroupText(alarmDays),
      alarmTimeRaw: try normalizedRoutineGroupText(alarmTime),
      weatherNotificationEnabled: weatherNotificationEnabled,
      routines: try routines?.makeDomainModels()
    )
  }
}

nonisolated private extension ActiveRoutineGroupResponseDTO {
  func makeDomainModel() throws -> ServerActiveRoutineGroup {
    guard let routineGroupID = routineGroupId,
          routineGroupID > 0 else {
      throw AccountRoutineGroupRemoteError.invalidResponse
    }

    return ServerActiveRoutineGroup(
      routineGroupID: routineGroupID,
      title: try normalizedRoutineGroupText(title),
      totalDurationSeconds: try validatedOptionalInt32Value(
        totalDurationSec
      ),
      completionRate: try validatedOptionalCompletionRate(
        completionRate
      ),
      routines: try routines?.makeDomainModels()
    )
  }
}

nonisolated private extension Array
where Element == ActiveRoutineItemResponseDTO {
  func makeDomainModels() throws -> [ServerActiveRoutineItem] {
    var seenRoutineIDs: Set<Int64> = []

    return try map { routine in
      try _Concurrency.Task<Never, Never>.checkCancellation()
      guard let routineID = routine.routineId,
            routineID > 0,
            seenRoutineIDs.insert(routineID).inserted else {
        throw AccountRoutineGroupRemoteError.invalidResponse
      }

      return ServerActiveRoutineItem(
        routineID: routineID,
        title: try normalizedRoutineGroupText(routine.title),
        isCompleted: routine.isCompleted,
        completedTimeSeconds: try validatedOptionalInt32Value(
          routine.completedTimeSec
        )
      )
    }
  }
}

nonisolated private extension TodayRoutineProgressResponseDTO {
  func makeDomainModel() throws -> ServerTodayRoutineProgress {
    guard let completedCount = try validatedOptionalInt32Value(
            completedCount
          ),
          let totalCount = try validatedOptionalInt32Value(totalCount),
          completedCount <= totalCount,
          let completionRate = try validatedOptionalCompletionRate(
            completionRate
          ) else {
      throw AccountRoutineGroupRemoteError.invalidResponse
    }

    return ServerTodayRoutineProgress(
      completedCount: completedCount,
      totalCount: totalCount,
      completionRate: completionRate
    )
  }
}

nonisolated private extension RoutineGroupActivationResponseDTO {
  func makeDomainModel(
    expectedRoutineGroupID: Int64,
    expectedIsActive: Bool
  ) throws -> ServerRoutineGroupActivation {
    guard let routineGroupID = routineGroupId,
          routineGroupID > 0,
          routineGroupID == expectedRoutineGroupID,
          let isActive,
          isActive == expectedIsActive else {
      throw AccountRoutineGroupRemoteError.invalidResponse
    }

    return ServerRoutineGroupActivation(
      routineGroupID: routineGroupID,
      isActive: isActive
    )
  }
}

nonisolated private extension Array
where Element == RoutineGroupRoutineResponseDTO {
  func makeDomainModels() throws -> [ServerRoutineItem] {
    var seenRoutineIDs: Set<Int64> = []

    return try map { routine in
      try _Concurrency.Task<Never, Never>.checkCancellation()
      guard let routineID = routine.routineId,
            routineID > 0,
            seenRoutineIDs.insert(routineID).inserted else {
        throw AccountRoutineGroupRemoteError.invalidResponse
      }

      return ServerRoutineItem(
        routineID: routineID,
        title: try normalizedRoutineGroupText(routine.title),
        type: try ServerRoutineItemType(serverValue: routine.type),
        durationSeconds: try validatedOptionalInt32Value(
          routine.durationSecond
        ),
        steps: try routine.steps?.makeDomainModels()
      )
    }
  }
}

nonisolated private extension Array
where Element == RoutineGroupStepResponseDTO {
  func makeDomainModels() throws -> [ServerRoutineNestedStep] {
    var seenStepIDs: Set<Int64> = []

    return try map { step in
      try _Concurrency.Task<Never, Never>.checkCancellation()
      guard let stepID = step.stepId,
            stepID > 0,
            seenStepIDs.insert(stepID).inserted else {
        throw AccountRoutineGroupRemoteError.invalidResponse
      }

      return ServerRoutineNestedStep(
        stepID: stepID,
        content: try normalizedRoutineGroupText(step.content),
        orderIndex: try validatedOptionalInt32Value(step.orderIndex)
      )
    }
  }
}

nonisolated private extension ServerRoutineItemType {
  init?(serverValue: String?) throws {
    guard let serverValue else {
      return nil
    }

    guard let normalized = try normalizedRoutineGroupText(serverValue) else {
      throw AccountRoutineGroupRemoteError.invalidResponse
    }

    switch normalized {
    case "CHECK":
      self = .check
    case "TIMER":
      self = .timer
    case "INPUT":
      self = .input
    default:
      self = .unknown(normalized)
    }
  }
}

nonisolated private func normalizedRoutineGroupText(
  _ value: String?
) throws -> String? {
  guard let value else {
    return nil
  }

  let normalized = value.trimmingCharacters(
    in: .whitespacesAndNewlines
  )
  guard !normalized.isEmpty else {
    throw AccountRoutineGroupRemoteError.invalidResponse
  }
  return normalized
}

nonisolated private func validatedOptionalInt32Value(
  _ value: Int?
) throws -> Int? {
  guard let value else {
    return nil
  }
  guard (0...Int(Int32.max)).contains(value) else {
    throw AccountRoutineGroupRemoteError.invalidResponse
  }
  return value
}

nonisolated private func validatedOptionalCompletionRate(
  _ value: Int?
) throws -> Double? {
  guard let value else {
    return nil
  }
  guard (0...100).contains(value) else {
    throw AccountRoutineGroupRemoteError.invalidResponse
  }
  return Double(value) / 100
}
