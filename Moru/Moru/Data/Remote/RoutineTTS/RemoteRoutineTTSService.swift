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

  func fetchRoutineTTS(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> [ServerRoutineTTSItem] {
    guard routineGroupID > 0, memberID > 0 else {
      throw AccountRoutineTTSRemoteError.invalidRequest
    }

    return try await performAccountRequest {
      let response = try await apiClient.request(
        RoutineTTSTarget.list(routineGroupID: routineGroupID),
        as: [RoutineTTSResponseDTO].self,
        authorizedForMemberID: memberID
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try response.makeDomainModels()
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

nonisolated private extension Array where Element == RoutineTTSResponseDTO {
  func makeDomainModels() throws -> [ServerRoutineTTSItem] {
    var seenRoutineIDs: Set<Int64> = []

    return try map { routine in
      try _Concurrency.Task<Never, Never>.checkCancellation()
      guard let routineID = routine.routineId,
            routineID > 0,
            seenRoutineIDs.insert(routineID).inserted else {
        throw AccountRoutineTTSRemoteError.invalidResponse
      }

      return ServerRoutineTTSItem(
        routineID: routineID,
        title: try normalizedRoutineTTSText(routine.title),
        type: try ServerRoutineTTSRoutineType(
          serverValue: routine.type
        ),
        steps: try routine.steps?.makeDomainModels()
      )
    }
  }
}

nonisolated private extension Array
where Element == RoutineTTSStepResponseDTO {
  func makeDomainModels() throws -> [ServerRoutineTTSStep] {
    var seenStepIDs: Set<Int64> = []

    return try map { step in
      try _Concurrency.Task<Never, Never>.checkCancellation()
      guard let stepID = step.stepId,
            stepID > 0,
            seenStepIDs.insert(stepID).inserted else {
        throw AccountRoutineTTSRemoteError.invalidResponse
      }

      return ServerRoutineTTSStep(
        stepID: stepID,
        content: try normalizedRoutineTTSText(step.content),
        ttsIntro: try normalizedRoutineTTSText(step.ttsIntro),
        status: try ServerRoutineTTSStatus(
          serverValue: step.ttsStatus
        ),
        audioURL: try validatedRoutineTTSAudioURL(step.s3Url)
      )
    }
  }
}

nonisolated private extension ServerRoutineTTSRoutineType {
  init?(serverValue: String?) throws {
    guard let serverValue else {
      return nil
    }

    guard let normalized = try normalizedRoutineTTSText(serverValue) else {
      throw AccountRoutineTTSRemoteError.invalidResponse
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

nonisolated private extension ServerRoutineTTSStatus {
  init?(serverValue: String?) throws {
    guard let serverValue else {
      return nil
    }

    guard let normalized = try normalizedRoutineTTSText(serverValue) else {
      throw AccountRoutineTTSRemoteError.invalidResponse
    }

    switch normalized {
    case "PENDING":
      self = .pending
    case "COMPLETED":
      self = .completed
    case "FAILED":
      self = .failed
    default:
      self = .unknown(normalized)
    }
  }
}

nonisolated private func normalizedRoutineTTSText(
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

nonisolated private func validatedRoutineTTSAudioURL(
  _ value: String?
) throws -> URL? {
  guard let normalized = try normalizedRoutineTTSText(value) else {
    return nil
  }

  guard let components = URLComponents(string: normalized),
        components.scheme?.lowercased() == "https",
        components.host?.isEmpty == false,
        let url = components.url else {
    throw AccountRoutineTTSRemoteError.invalidResponse
  }
  return url
}
