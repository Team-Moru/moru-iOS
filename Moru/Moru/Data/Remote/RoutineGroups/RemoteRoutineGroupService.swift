//
//  RemoteRoutineGroupService.swift
//  Moru
//

import Foundation

nonisolated final class DefaultAccountRoutineGroupRemoteService:
  AccountRoutineGroupRemoteServing {
  private let apiClient: any AccountBoundRawResponseClient

  init(apiClient: any AccountBoundRawResponseClient) {
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
    identity: AccountSessionIdentity
  ) async throws -> ServerActiveRoutineGroup? {
    guard identity.memberID > 0 else {
      throw AccountRoutineGroupRemoteError.invalidRequest
    }

    return try await performAccountRequest {
      let response = try await apiClient.requestResponse(
        RoutineGroupTarget.active,
        authorizedFor: identity
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try decodeRoutineGroupReadPayload(
        ActiveRoutineGroupResponseDTO.self,
        from: response
      )?.makeDomainModel()
    }
  }

  func fetchTodayRoutineGroupSummary(
    identity: AccountSessionIdentity
  ) async throws -> ServerTodayRoutineGroupSummary? {
    guard identity.memberID > 0 else {
      throw AccountRoutineGroupRemoteError.invalidRequest
    }

    return try await performAccountRequest {
      let response = try await apiClient.requestResponse(
        RoutineGroupTarget.today,
        authorizedFor: identity
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try decodeRoutineGroupReadPayload(
        TodayRoutineGroupSummaryResponseDTO.self,
        from: response
      )?.makeDomainModel()
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

nonisolated private func decodeRoutineGroupReadPayload<Payload>(
  _ payloadType: Payload.Type,
  from response: AccountBoundHTTPResponse
) throws -> Payload? where Payload: Decodable & Sendable {
  let decoder = JSONDecoder()

  if (200..<300).contains(response.statusCode) {
    let envelope: APIResponse<Payload>
    do {
      envelope = try decoder.decode(
        APIResponse<Payload>.self,
        from: response.data
      )
    } catch {
      throw APIError.decoding(error.localizedDescription)
    }

    guard envelope.isSuccess else {
      throw APIError.server(
        statusCode: response.statusCode,
        code: envelope.code,
        message: envelope.message
      )
    }
    guard let result = envelope.result else {
      throw APIError.missingResult(
        code: envelope.code,
        message: envelope.message
      )
    }
    return result
  }

  if response.statusCode == 404,
     let envelope = try? decoder.decode(
       RoutineGroupNoActiveErrorEnvelope.self,
       from: response.data
     ),
     envelope.isSuccess == false,
     envelope.code == "ROUTINE4005",
     envelope.message == "사용 중인 루틴이 없습니다.",
     !envelope.containsResult {
    return nil
  }

  let serverError = try? decoder.decode(
    ServerErrorResponse.self,
    from: response.data
  )
  throw APIError.server(
    statusCode: response.statusCode,
    code: serverError?.code,
    message: serverError?.message ?? HTTPURLResponse.localizedString(
      forStatusCode: response.statusCode
    )
  )
}

nonisolated private struct RoutineGroupNoActiveErrorEnvelope: Decodable {
  let isSuccess: Bool
  let code: String
  let message: String
  let containsResult: Bool

  private enum CodingKeys: String, CodingKey {
    case isSuccess
    case code
    case message
    case result
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    isSuccess = try container.decode(Bool.self, forKey: .isSuccess)
    code = try container.decode(String.self, forKey: .code)
    message = try container.decode(String.self, forKey: .message)
    containsResult = container.contains(.result)
  }
}

nonisolated private extension ActiveRoutineGroupResponseDTO {
  func makeDomainModel() throws -> ServerActiveRoutineGroup {
    guard let routineGroupID = routineGroupId,
          routineGroupID > 0,
          let title = try normalizedRequiredRoutineGroupText(title),
          let totalDurationSec = try validatedRequiredInt32Value(
            totalDurationSec
          ),
          let completionRate = try normalizedCompletionRate(
            completionRate
          ),
          let routines else {
      throw AccountRoutineGroupRemoteError.invalidResponse
    }

    return ServerActiveRoutineGroup(
      routineGroupID: routineGroupID,
      title: title,
      totalDurationSeconds: totalDurationSec,
      completionRate: completionRate,
      routines: try routines.makeActiveDomainModels()
    )
  }
}

nonisolated private extension Array where Element == ActiveRoutineResponseDTO {
  func makeActiveDomainModels() throws -> [ServerActiveRoutine] {
    var seenRoutineIDs: Set<Int64> = []

    return try map { routine in
      try _Concurrency.Task<Never, Never>.checkCancellation()
      guard let routineID = routine.routineId,
            routineID > 0,
            seenRoutineIDs.insert(routineID).inserted,
            let title = try normalizedRequiredRoutineGroupText(
              routine.title
            ),
            let isCompleted = routine.isCompleted else {
        throw AccountRoutineGroupRemoteError.invalidResponse
      }

      return ServerActiveRoutine(
        routineID: routineID,
        title: title,
        isCompleted: isCompleted,
        completedTimeSeconds: try validatedOptionalInt32Value(
          routine.completedTimeSec
        )
      )
    }
  }
}

nonisolated private extension TodayRoutineGroupSummaryResponseDTO {
  func makeDomainModel() throws -> ServerTodayRoutineGroupSummary {
    guard let completedCount = try validatedRequiredInt32Value(
            completedCount
          ),
          let totalCount = try validatedRequiredInt32Value(totalCount),
          completedCount <= totalCount,
          let completionRate = try normalizedCompletionRate(
            completionRate
          ) else {
      throw AccountRoutineGroupRemoteError.invalidResponse
    }

    return ServerTodayRoutineGroupSummary(
      completedCount: completedCount,
      totalCount: totalCount,
      completionRate: completionRate
    )
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

nonisolated private func normalizedRequiredRoutineGroupText(
  _ value: String?
) throws -> String? {
  guard let normalized = try normalizedRoutineGroupText(value) else {
    return nil
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

nonisolated private func validatedRequiredInt32Value(
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

nonisolated private func normalizedCompletionRate(
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
