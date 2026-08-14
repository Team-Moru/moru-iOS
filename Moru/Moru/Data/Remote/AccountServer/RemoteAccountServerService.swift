//
//  RemoteAccountServerService.swift
//  Moru
//

import Foundation

nonisolated final class DefaultAccountServerRemoteService:
  AccountServerRemoteServing {
  private let apiClient: any AccountBoundAPIClient

  init(apiClient: any AccountBoundAPIClient) {
    self.apiClient = apiClient
  }

  func fetchProfile(
    memberID: Int64
  ) async throws -> ServerAccountProfile {
    guard memberID > 0 else {
      throw AccountServerRemoteError.invalidRequest
    }

    return try await performAccountRequest {
      let response = try await apiClient.request(
        AccountServerTarget.profile,
        as: AccountProfileResponseDTO.self,
        authorizedForMemberID: memberID
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try response.makeDomainModel(expectedMemberID: memberID)
    }
  }

  func fetchStreak(
    memberID: Int64
  ) async throws -> ServerAccountStreak {
    guard memberID > 0 else {
      throw AccountServerRemoteError.invalidRequest
    }

    return try await performAccountRequest {
      let response = try await apiClient.request(
        AccountServerTarget.streak,
        as: AccountStreakResponseDTO.self,
        authorizedForMemberID: memberID
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try response.makeDomainModel()
    }
  }

  func fetchVoices(
    memberID: Int64
  ) async throws -> [ServerTTSVoice] {
    guard memberID > 0 else {
      throw AccountServerRemoteError.invalidRequest
    }

    return try await performAccountRequest {
      let response = try await apiClient.request(
        AccountServerTarget.voices,
        as: TTSVoiceListResponseDTO.self,
        authorizedForMemberID: memberID
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try response.makeDomainModel()
    }
  }

  func updateTTS(
    ttsID: Int64,
    memberID: Int64
  ) async throws -> ServerTTSSelection {
    guard memberID > 0, ttsID > 0 else {
      throw AccountServerRemoteError.invalidRequest
    }

    return try await performAccountRequest {
      let response = try await apiClient.request(
        AccountServerTarget.updateTTS(
          TTSUpdateRequestDTO(ttsId: ttsID)
        ),
        as: TTSUpdateResponseDTO.self,
        authorizedForMemberID: memberID
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try response.makeDomainModel(
        expectedMemberID: memberID,
        expectedTTSID: ttsID
      )
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
      throw AccountServerRemoteError.accountAuthorizationChanged
    }
  }
}

nonisolated private extension AccountProfileResponseDTO {
  func makeDomainModel(
    expectedMemberID: Int64
  ) throws -> ServerAccountProfile {
    guard let memberId,
          memberId > 0,
          memberId == expectedMemberID,
          let nickname = try normalizedRequiredText(nickname),
          let loginType = try normalizedRequiredText(loginType),
          let ttsId,
          ttsId > 0 else {
      throw AccountServerRemoteError.invalidResponse
    }

    return ServerAccountProfile(
      memberID: memberId,
      nickname: nickname,
      loginType: ServerAccountLoginType(serverValue: loginType),
      profileImageKey: try normalizedOptionalText(profileImageKey),
      selectedTTSID: ttsId
    )
  }
}

nonisolated private extension AccountStreakResponseDTO {
  func makeDomainModel() throws -> ServerAccountStreak {
    guard let currentStreak,
          currentStreak >= 0,
          let currentDays = Int(exactly: currentStreak),
          let maxStreak,
          maxStreak >= 0,
          let bestDays = Int(exactly: maxStreak),
          let weeklyStatus,
          weeklyStatus.count == 7 else {
      throw AccountServerRemoteError.invalidResponse
    }

    return ServerAccountStreak(
      currentDays: currentDays,
      bestDays: bestDays,
      weeklyStatus: weeklyStatus
    )
  }
}

nonisolated private extension TTSVoiceListResponseDTO {
  func makeDomainModel() throws -> [ServerTTSVoice] {
    guard let voices else {
      throw AccountServerRemoteError.invalidResponse
    }

    var seenTTSIDs: Set<Int64> = []

    return try voices.map { voice in
      guard let ttsId = voice.ttsId,
            ttsId > 0,
            seenTTSIDs.insert(ttsId).inserted,
            let voiceCode = try normalizedRequiredText(
              voice.voiceCode
            ),
            let displayName = try normalizedRequiredText(
              voice.displayName
            ),
            let description = try normalizedRequiredText(
              voice.description
            ),
            let proOnly = voice.proOnly else {
        throw AccountServerRemoteError.invalidResponse
      }
      let previewAudioURL = try previewAudioURL(from: voice.previewAudioUrl)

      return ServerTTSVoice(
        ttsID: ttsId,
        voiceCode: voiceCode,
        displayName: displayName,
        description: description,
        isProOnly: proOnly,
        previewAudioURL: previewAudioURL
      )
    }
  }
}

nonisolated private extension TTSUpdateResponseDTO {
  func makeDomainModel(
    expectedMemberID: Int64,
    expectedTTSID: Int64
  ) throws -> ServerTTSSelection {
    guard let memberId,
          memberId > 0,
          memberId == expectedMemberID,
          let ttsId,
          ttsId > 0,
          ttsId == expectedTTSID,
          let voiceCode = try normalizedRequiredText(voiceCode),
          let displayName = try normalizedRequiredText(displayName) else {
      throw AccountServerRemoteError.invalidResponse
    }

    return ServerTTSSelection(
      memberID: memberId,
      ttsID: ttsId,
      voiceCode: voiceCode,
      displayName: displayName
    )
  }
}

nonisolated private extension ServerAccountLoginType {
  init(serverValue: String) {
    switch serverValue {
    case "GOOGLE":
      self = .google
    case "NAVER":
      self = .naver
    case "KAKAO":
      self = .kakao
    case "APPLE":
      self = .apple
    default:
      self = .unknown(serverValue)
    }
  }
}

nonisolated private func normalizedRequiredText(
  _ value: String?
) throws -> String? {
  guard let value else {
    return nil
  }

  let normalized = value.trimmingCharacters(
    in: .whitespacesAndNewlines
  )
  guard !normalized.isEmpty else {
    throw AccountServerRemoteError.invalidResponse
  }
  return normalized
}

nonisolated private func normalizedOptionalText(
  _ value: String?
) throws -> String? {
  guard let value else {
    return nil
  }
  return try normalizedRequiredText(value)
}

nonisolated private func previewAudioURL(
  from value: String?
) throws -> URL? {
  guard let normalized = try normalizedOptionalText(value) else {
    return nil
  }
  guard let url = URL(string: normalized),
        url.scheme?.lowercased() == "https",
        let host = url.host,
        !host.isEmpty,
        url.port == nil || url.port == 443,
        url.user == nil,
        url.password == nil,
        url.fragment == nil else {
    throw AccountServerRemoteError.invalidResponse
  }
  return url
}
