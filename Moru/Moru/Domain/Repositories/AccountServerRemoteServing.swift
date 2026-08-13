//
//  AccountServerRemoteServing.swift
//  Moru
//

import Foundation

nonisolated protocol AccountServerRemoteServing: Sendable {
  func fetchProfile(memberID: Int64) async throws -> ServerAccountProfile
  func fetchStreak(memberID: Int64) async throws -> ServerAccountStreak
  func fetchVoices(memberID: Int64) async throws -> [ServerTTSVoice]
  func updateTTS(
    ttsID: Int64,
    memberID: Int64
  ) async throws -> ServerTTSSelection
}

nonisolated enum AccountServerRemoteError:
  Error,
  Equatable,
  Sendable {
  case invalidRequest
  case invalidResponse
  case accountAuthorizationChanged
}
