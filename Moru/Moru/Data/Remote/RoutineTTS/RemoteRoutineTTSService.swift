//
//  RemoteRoutineTTSService.swift
//  Moru
//

import Foundation

nonisolated final class DefaultRoutineTTSRemoteService:
  RoutineTTSRemoteServing {
  private let apiClient: any AccountBoundAPIClient
  private let decoder: JSONDecoder

  init(
    apiClient: any AccountBoundAPIClient,
    decoder: sending JSONDecoder = JSONDecoder()
  ) {
    self.apiClient = apiClient
    self.decoder = decoder
  }

  func fetchRoutineTTS(
    routineGroupID: Int64,
    identity: AccountSessionIdentity
  ) async throws -> [ServerRoutineTTSRoutine] {
    guard routineGroupID > 0, identity.memberID > 0 else {
      throw RoutineTTSRemoteError.invalidRequest
    }

    do {
      let data = try await apiClient.requestData(
        RoutineTTSTarget.list(routineGroupID: routineGroupID),
        authorizedFor: identity
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()

      let envelope: APIResponse<[RoutineTTSResponseDTO]>
      do {
        envelope = try decoder.decode(
          APIResponse<[RoutineTTSResponseDTO]>.self,
          from: data
        )
      } catch {
        throw RoutineTTSRemoteError.invalidResponse
      }

      guard envelope.isSuccess, let response = envelope.result else {
        throw RoutineTTSRemoteError.invalidResponse
      }
      return try response.makeDomainModels()
    } catch is CancellationError {
      throw CancellationError()
    } catch APIError.cancelled {
      throw CancellationError()
    } catch is AccountAuthorizationContextError {
      throw RoutineTTSRemoteError.accountAuthorizationChanged
    }
  }
}

nonisolated private extension Array
where Element == RoutineTTSResponseDTO {
  func makeDomainModels() throws -> [ServerRoutineTTSRoutine] {
    var seenRoutineIDs: Set<Int64> = []
    var seenStepIDs: Set<Int64> = []

    return try map { routine in
      try _Concurrency.Task<Never, Never>.checkCancellation()
      guard let routineID = routine.routineId,
            routineID > 0,
            seenRoutineIDs.insert(routineID).inserted,
            let steps = routine.steps else {
        throw RoutineTTSRemoteError.invalidResponse
      }

      return ServerRoutineTTSRoutine(
        routineID: routineID,
        title: try requiredRoutineTTSText(routine.title),
        type: try ServerRoutineTTSRoutineType(serverValue: routine.type),
        steps: try steps.makeDomainModels(seenStepIDs: &seenStepIDs)
      )
    }
  }
}

nonisolated private extension Array
where Element == RoutineTTSStepResponseDTO {
  func makeDomainModels(
    seenStepIDs: inout Set<Int64>
  ) throws -> [ServerRoutineTTSStep] {
    try map { step in
      try _Concurrency.Task<Never, Never>.checkCancellation()
      guard let stepID = step.stepId,
            stepID > 0,
            seenStepIDs.insert(stepID).inserted else {
        throw RoutineTTSRemoteError.invalidResponse
      }

      let status = try ServerRoutineTTSGenerationStatus(
        serverValue: step.ttsStatus
      )
      let introText = normalizedOptionalRoutineTTSText(step.ttsIntro)

      return ServerRoutineTTSStep(
        stepID: stepID,
        content: try requiredRoutineTTSText(step.content),
        introText: introText,
        status: status,
        audioURL: playableAudioURL(
          status: status,
          introText: introText,
          serverValue: step.s3Url
        )
      )
    }
  }
}

nonisolated private extension ServerRoutineTTSRoutineType {
  init(serverValue: String?) throws {
    switch try requiredRoutineTTSText(serverValue) {
    case "CHECK":
      self = .check
    case "TIMER":
      self = .timer
    case "INPUT":
      self = .input
    default:
      throw RoutineTTSRemoteError.invalidResponse
    }
  }
}

nonisolated private extension ServerRoutineTTSGenerationStatus {
  init(serverValue: String?) throws {
    let value = try requiredRoutineTTSText(serverValue)
    switch value {
    case "PENDING":
      self = .pending
    case "COMPLETED":
      self = .completed
    case "FAILED":
      self = .failed
    default:
      self = .unknown(value)
    }
  }
}

nonisolated private func requiredRoutineTTSText(
  _ value: String?
) throws -> String {
  guard let normalized = normalizedOptionalRoutineTTSText(value) else {
    throw RoutineTTSRemoteError.invalidResponse
  }
  return normalized
}

nonisolated private func normalizedOptionalRoutineTTSText(
  _ value: String?
) -> String? {
  guard let value else {
    return nil
  }
  let normalized = value.trimmingCharacters(
    in: .whitespacesAndNewlines
  )
  return normalized.isEmpty ? nil : normalized
}

nonisolated private func playableAudioURL(
  status: ServerRoutineTTSGenerationStatus,
  introText: String?,
  serverValue: String?
) -> URL? {
  guard status == .completed,
        introText != nil,
        let normalizedURL = normalizedOptionalRoutineTTSText(serverValue),
        let url = URL(string: normalizedURL),
        url.scheme?.lowercased() == "https",
        let host = url.host,
        !host.isEmpty,
        url.user == nil,
        url.password == nil else {
    return nil
  }
  return url
}
