//
//  AuthDTO.swift
//  Moru
//

import Foundation

nonisolated struct SocialLoginRequestDTO: Encodable, Equatable, Sendable {
  let token: String
  let authorizationCode: String?
}

nonisolated struct AppleLoginRequestDTO: Encodable, Equatable, Sendable {
  let provider = "APPLE"
  let identityToken: String
  let authorizationCode: String?
}

nonisolated struct LoginResponseDTO: Decodable, Equatable, Sendable {
  let memberId: Int64
  let accessToken: String
  let refreshToken: String
  let isNewMember: Bool?
  let onboardingCompleted: Bool
}

nonisolated struct TokenReissueResponseDTO: Decodable, Equatable, Sendable {
  let accessToken: String
  let refreshToken: String
  let tokenType: String
  let memberId: Int64
  let onboardingCompleted: Bool
}

nonisolated struct LogoutRequestDTO: Encodable, Equatable, Sendable {
  let refreshToken: String
}

nonisolated enum WithdrawalStatusDTO: String, Decodable, Equatable, Sendable {
  case completed = "COMPLETED"
}

nonisolated struct WithdrawalResponseDTO: Decodable, Equatable, Sendable {
  let status: WithdrawalStatusDTO
  let message: String

  init(
    status: WithdrawalStatusDTO,
    message: String
  ) {
    self.status = status
    self.message = message
  }
}
