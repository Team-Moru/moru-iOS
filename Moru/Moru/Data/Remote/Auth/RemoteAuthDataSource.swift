//
//  RemoteAuthDataSource.swift
//  Moru
//

import Foundation

nonisolated protocol AuthRemoteDataSource: Sendable {
  func login(
    provider: AuthProvider,
    request: SocialLoginRequestDTO
  ) async throws -> LoginResponseDTO

  func reissue(refreshToken: String) async throws -> TokenReissueResponseDTO

  func logout(refreshToken: String) async throws

  func withdraw() async throws -> WithdrawalResponseDTO
}

nonisolated enum AuthRemoteDataSourceError: Error, Equatable, Sendable {
  case unsupportedProvider(String)
  case invalidSocialToken
  case invalidRefreshToken
}

nonisolated final class DefaultAuthRemoteDataSource: AuthRemoteDataSource {
  private let apiClient: any APIClient

  init(apiClient: any APIClient) {
    self.apiClient = apiClient
  }

  func login(
    provider: AuthProvider,
    request: SocialLoginRequestDTO
  ) async throws -> LoginResponseDTO {
    if case .unknown(let value) = provider {
      throw AuthRemoteDataSourceError.unsupportedProvider(value)
    }

    guard !request.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AuthRemoteDataSourceError.invalidSocialToken
    }

    return try await apiClient.request(
      AuthTarget.login(provider: provider, request: request),
      as: LoginResponseDTO.self
    )
  }

  func reissue(refreshToken: String) async throws -> TokenReissueResponseDTO {
    guard !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AuthRemoteDataSourceError.invalidRefreshToken
    }

    return try await apiClient.request(
      AuthTarget.reissue(refreshToken: refreshToken),
      as: TokenReissueResponseDTO.self
    )
  }

  func logout(refreshToken: String) async throws {
    guard !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AuthRemoteDataSourceError.invalidRefreshToken
    }

    try await apiClient.requestVoid(
      AuthTarget.logout(
        request: LogoutRequestDTO(refreshToken: refreshToken)
      )
    )
  }

  func withdraw() async throws -> WithdrawalResponseDTO {
    try await apiClient.request(
      AuthTarget.withdrawal,
      as: WithdrawalResponseDTO.self
    )
  }
}
