//
//  AccountEntryViewModel.swift
//  Moru
//
//  Created by Codex on 7/27/26.
//

import Foundation
import Observation

nonisolated enum AccountEntryProvider: Equatable, Sendable {
  case apple
  case google
  case kakao
}

nonisolated enum AccountEntryFailure: Equatable, Sendable {
  case offline
  case unauthorized
  case serviceUnavailable
  case keychain
  case invalidStoredCredentials
  case unavailable
}

nonisolated enum AccountEntryStatus: Equatable, Sendable {
  case idle
  case loading
  case cancelled
  case failure(AccountEntryFailure)
}

nonisolated enum AccountEntryFailureMapper {
  static func failure(for error: Error) -> AccountEntryFailure? {
    if let apiError = error as? APIError {
      return failure(for: apiError)
    }

    if let credentialError = error as? CredentialStoreError {
      switch credentialError {
      case .keychain:
        return .keychain
      case .invalidCredentials, .invalidStoredData:
        return .invalidStoredCredentials
      }
    }

    return .unavailable
  }

  private static func failure(for error: APIError) -> AccountEntryFailure? {
    switch error {
    case .cancelled:
      return nil
    case .transport(let code, _):
      return offlineErrorCodes.contains(code) ? .offline : .serviceUnavailable
    case .server(let statusCode, _, _):
      if statusCode == 401 {
        return .unauthorized
      }
      return (500..<600).contains(statusCode)
        ? .serviceUnavailable
        : .unavailable
    case .authenticationRequired:
      return .unauthorized
    case .invalidRequest,
         .capabilityDisabled,
         .decoding,
         .missingResult:
      return .unavailable
    }
  }

  private static let offlineErrorCodes: Set<Int> = [
    URLError.notConnectedToInternet.rawValue,
    URLError.networkConnectionLost.rawValue,
    URLError.cannotConnectToHost.rawValue,
    URLError.cannotFindHost.rawValue,
    URLError.dataNotAllowed.rawValue,
    URLError.internationalRoamingOff.rawValue,
  ]
}

@MainActor
@Observable
final class AccountEntryViewModel {
  private let socialLoginCoordinator: any SocialLoginCoordinating

  private(set) var status: AccountEntryStatus
  private(set) var activeProvider: AccountEntryProvider?
  private var handledRestorationFailure = false

  var isRequestInFlight: Bool {
    activeProvider != nil
  }

  init(
    socialLoginCoordinator: any SocialLoginCoordinating,
    status: AccountEntryStatus = .idle
  ) {
    self.socialLoginCoordinator = socialLoginCoordinator
    self.status = status
  }

  @discardableResult
  func authorizationWillBegin(
    provider: AccountEntryProvider
  ) -> Bool {
    guard activeProvider == nil else {
      return false
    }

    activeProvider = provider
    status = .loading
    return true
  }

  func authorizationPreparationDidFail() {
    guard activeProvider != nil else {
      return
    }

    activeProvider = nil
    status = .failure(.unavailable)
  }

  @discardableResult
  func authorizationDidComplete(
    _ outcome: SocialAuthorizationOutcome
  ) async -> Bool {
    guard activeProvider != nil else {
      return false
    }

    defer { activeProvider = nil }

    switch outcome {
    case .cancelled:
      status = .cancelled
      return false
    case .failed:
      status = .failure(.unavailable)
      return false
    case .authorized(let authorization):
      do {
        try await socialLoginCoordinator.login(with: authorization)
        status = .idle
        return true
      } catch APIError.cancelled {
        status = .cancelled
        return false
      } catch {
        status = .failure(
          AccountEntryFailureMapper.failure(for: error) ?? .unavailable
        )
        return false
      }
    }
  }

  func accountRestorationDidFail(_ failure: AccountSessionFailure) {
    guard !handledRestorationFailure,
          activeProvider == nil else {
      return
    }

    handledRestorationFailure = true
    switch failure {
    case .invalidCredentials:
      status = .failure(.invalidStoredCredentials)
    case .credentialStoreUnavailable:
      status = .failure(.keychain)
    }
  }
}
