//
//  RemoteRoutineTTSService.swift
//  Moru
//

import Foundation

nonisolated final class DefaultAccountRoutineTTSRemoteService:
  AccountRoutineTTSRemoteServing {
  private let apiClient: any AccountBoundAPIClient

  init(apiClient: any AccountBoundAPIClient) {
    self.apiClient = apiClient
  }

  func createRoutineGroup(
    _ request: ServerRoutineGroupCreationRequest,
    memberID: Int64
  ) async throws -> ServerRoutineGroupCreationResult {
    guard memberID > 0 else {
      throw AccountRoutineTTSRemoteError.invalidRequest
    }

    let requestDTO = try request.makeRequestDTO()

    return try await performAccountRequest {
      let response = try await apiClient.request(
        RoutineGroupTarget.create(requestDTO),
        as: RoutineGroupDetailResponseDTO.self,
        authorizedForMemberID: memberID
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try response.makeCreationResult(matching: request)
    }
  }

  func deleteRoutineGroup(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> ServerRoutineGroupDeletionResult {
    guard memberID > 0, routineGroupID > 0 else {
      throw AccountRoutineTTSRemoteError.invalidRequest
    }

    return try await performAccountRequest {
      let response = try await apiClient.request(
        RoutineGroupTarget.delete(routineGroupID: routineGroupID),
        as: RoutineGroupDeleteResponseDTO.self,
        authorizedForMemberID: memberID
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()

      if let acknowledgedID = response.routineId,
         acknowledgedID <= 0 {
        throw AccountRoutineTTSRemoteError.invalidResponse
      }

      return ServerRoutineGroupDeletionResult(
        requestedRoutineGroupID: routineGroupID,
        serverAcknowledgedRoutineID: response.routineId
      )
    }
  }

  func fetchRoutineTTS(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> ServerRoutineTTSManifest {
    guard memberID > 0, routineGroupID > 0 else {
      throw AccountRoutineTTSRemoteError.invalidRequest
    }

    return try await performAccountRequest {
      let response = try await apiClient.request(
        RoutineTTSTarget.manifest(routineGroupID: routineGroupID),
        as: [RoutineTTSResponseDTO].self,
        authorizedForMemberID: memberID
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try response.makeManifest(routineGroupID: routineGroupID)
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
      throw AccountRoutineTTSRemoteError.accountAuthorizationChanged
    }
  }
}

nonisolated private extension ServerRoutineGroupCreationRequest {
  func makeRequestDTO() throws -> RoutineGroupCreateRequestDTO {
    let normalizedTitle = try requiredRequestText(title)
    let normalizedDescription = try optionalRequestText(description)
    let normalizedAlarmDays = try optionalRequestText(alarmDaysRaw)
    let normalizedAlarmTime = try optionalRequestText(alarmTimeRaw)

    if let normalizedAlarmTime {
      try validateAlarmTime(normalizedAlarmTime)
    }

    guard !routines.isEmpty else {
      throw AccountRoutineTTSRemoteError.invalidRequest
    }

    var localStepIDs: Set<UUID> = []
    let routineDTOs = try routines.map { routine in
      guard localStepIDs.insert(routine.localStepID).inserted,
            (1...Int(Int32.max)).contains(routine.durationSeconds) else {
        throw AccountRoutineTTSRemoteError.invalidRequest
      }

      return RoutineCreateRequestDTO(
        title: try requiredRequestText(routine.title),
        type: routine.type.serverValue,
        durationSecond: routine.durationSeconds
      )
    }

    return RoutineGroupCreateRequestDTO(
      title: normalizedTitle,
      description: normalizedDescription,
      alarmDays: normalizedAlarmDays,
      alarmTime: normalizedAlarmTime,
      weatherNotificationEnabled: weatherNotificationEnabled,
      routines: routineDTOs
    )
  }
}

nonisolated private extension RoutineGroupDetailResponseDTO {
  func makeCreationResult(
    matching request: ServerRoutineGroupCreationRequest
  ) throws -> ServerRoutineGroupCreationResult {
    guard let routineGroupID = routineGroupId,
          routineGroupID > 0,
          let responseRoutines = routines,
          responseRoutines.count == request.routines.count else {
      throw AccountRoutineTTSRemoteError.invalidResponse
    }

    var routineIDs: Set<Int64> = []
    var stepIDs: Set<Int64> = []
    let createdRoutines = try zip(
      request.routines,
      responseRoutines
    ).map { requested, response in
      let requestedTitle = try requiredRequestText(requested.title)

      guard let routineID = response.routineId,
            routineID > 0,
            routineIDs.insert(routineID).inserted,
            let responseTitle = try requiredResponseText(response.title),
            responseTitle == requestedTitle,
            let responseType = try creationItemType(response.type),
            responseType == requested.type,
            let durationSeconds = response.durationSecond,
            durationSeconds == requested.durationSeconds,
            let responseSteps = response.steps else {
        throw AccountRoutineTTSRemoteError.invalidResponse
      }

      var orderIndices: Set<Int> = []
      let createdSteps = try responseSteps.map { step in
        guard let stepID = step.stepId,
              stepID > 0,
              stepIDs.insert(stepID).inserted,
              let orderIndex = step.orderIndex,
              (0...Int(Int32.max)).contains(orderIndex),
              orderIndices.insert(orderIndex).inserted else {
          throw AccountRoutineTTSRemoteError.invalidResponse
        }

        return ServerCreatedRoutineStep(
          stepID: stepID,
          content: try optionalResponseText(step.content),
          orderIndex: orderIndex
        )
      }
      .sorted { $0.orderIndex < $1.orderIndex }

      return ServerCreatedRoutine(
        localStepID: requested.localStepID,
        routineID: routineID,
        title: responseTitle,
        type: responseType,
        durationSeconds: durationSeconds,
        steps: createdSteps
      )
    }

    return ServerRoutineGroupCreationResult(
      localRoutineID: request.localRoutineID,
      routineGroupID: routineGroupID,
      routines: createdRoutines
    )
  }
}

nonisolated private extension Array where Element == RoutineTTSResponseDTO {
  func makeManifest(
    routineGroupID: Int64
  ) throws -> ServerRoutineTTSManifest {
    var routineIDs: Set<Int64> = []
    var stepIDs: Set<Int64> = []

    let mappedRoutines = try map { routine in
      guard let routineID = routine.routineId,
            routineID > 0,
            routineIDs.insert(routineID).inserted,
            let steps = routine.steps else {
        throw AccountRoutineTTSRemoteError.invalidResponse
      }

      let mappedSteps = try steps.map { step in
        guard let stepID = step.stepId,
              stepID > 0,
              stepIDs.insert(stepID).inserted,
              let status = try ttsStatus(step.ttsStatus) else {
          throw AccountRoutineTTSRemoteError.invalidResponse
        }

        let audioURL = try optionalHTTPSURL(step.s3Url)
        if status == .completed, audioURL == nil {
          throw AccountRoutineTTSRemoteError.invalidResponse
        }

        return ServerRoutineTTSStep(
          stepID: stepID,
          content: try optionalResponseText(step.content),
          synthesizedIntro: try optionalResponseText(step.ttsIntro),
          status: status,
          audioURL: audioURL
        )
      }

      return ServerRoutineTTSItem(
        routineID: routineID,
        title: try optionalResponseText(routine.title),
        type: try optionalRoutineItemType(routine.type),
        steps: mappedSteps
      )
    }

    return ServerRoutineTTSManifest(
      routineGroupID: routineGroupID,
      routines: mappedRoutines
    )
  }
}

nonisolated private extension ServerRoutineCreationItemType {
  var serverValue: String {
    switch self {
    case .check:
      "CHECK"
    case .timer:
      "TIMER"
    case .input:
      "INPUT"
    }
  }
}

nonisolated private func creationItemType(
  _ value: String?
) throws -> ServerRoutineCreationItemType? {
  guard let value = try optionalResponseText(value) else {
    return nil
  }

  switch value {
  case "CHECK":
    return .check
  case "TIMER":
    return .timer
  case "INPUT":
    return .input
  default:
    throw AccountRoutineTTSRemoteError.invalidResponse
  }
}

nonisolated private func optionalRoutineItemType(
  _ value: String?
) throws -> ServerRoutineItemType? {
  guard let value = try optionalResponseText(value) else {
    return nil
  }

  switch value {
  case "CHECK":
    return .check
  case "TIMER":
    return .timer
  case "INPUT":
    return .input
  default:
    return .unknown(value)
  }
}

nonisolated private func ttsStatus(
  _ value: String?
) throws -> ServerRoutineTTSStatus? {
  guard let value = try optionalResponseText(value) else {
    return nil
  }

  switch value {
  case "PENDING":
    return .pending
  case "COMPLETED":
    return .completed
  case "FAILED":
    return .failed
  default:
    return .unknown(value)
  }
}

nonisolated private func requiredRequestText(
  _ value: String
) throws -> String {
  let normalized = value.trimmingCharacters(
    in: .whitespacesAndNewlines
  )
  guard !normalized.isEmpty else {
    throw AccountRoutineTTSRemoteError.invalidRequest
  }
  return normalized
}

nonisolated private func optionalRequestText(
  _ value: String?
) throws -> String? {
  guard let value else {
    return nil
  }
  return try requiredRequestText(value)
}

nonisolated private func requiredResponseText(
  _ value: String?
) throws -> String? {
  guard let value else {
    return nil
  }
  return try optionalResponseText(value)
}

nonisolated private func optionalResponseText(
  _ value: String?
) throws -> String? {
  guard let value else {
    return nil
  }

  let normalized = value.trimmingCharacters(
    in: .whitespacesAndNewlines
  )
  guard !normalized.isEmpty else {
    throw AccountRoutineTTSRemoteError.invalidResponse
  }
  return normalized
}

nonisolated private func validateAlarmTime(_ value: String) throws {
  let components = value.split(
    separator: ":",
    omittingEmptySubsequences: false
  )
  guard value.count == 5,
        components.count == 2,
        components[0].count == 2,
        components[1].count == 2,
        let hour = Int(components[0]),
        (0...23).contains(hour),
        let minute = Int(components[1]),
        (0...59).contains(minute) else {
    throw AccountRoutineTTSRemoteError.invalidRequest
  }
}

nonisolated private func optionalHTTPSURL(
  _ value: String?
) throws -> URL? {
  guard let value = try optionalResponseText(value) else {
    return nil
  }
  guard let url = URL(string: value),
        url.scheme?.lowercased() == "https",
        let host = url.host,
        !host.isEmpty else {
    throw AccountRoutineTTSRemoteError.invalidResponse
  }
  return url
}
