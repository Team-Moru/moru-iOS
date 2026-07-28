//
//  AppleLoginReadiness.swift
//  Moru
//

import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security

nonisolated struct AppleAuthorizationRequestContext: Equatable, Sendable {
  let rawNonce: String
  let hashedNonce: String
}

nonisolated extension AppleAuthorizationRequestContext:
  CustomDebugStringConvertible,
  CustomStringConvertible {
  var description: String {
    "AppleAuthorizationRequestContext(rawNonce: <redacted>, hashedNonce: <redacted>)"
  }

  var debugDescription: String {
    description
  }
}

nonisolated protocol AppleNonceGenerating: Sendable {
  func makeContext() throws -> AppleAuthorizationRequestContext
}

nonisolated enum AppleNonceGenerationError: Error, Equatable, Sendable {
  case randomBytes(OSStatus)
}

nonisolated struct SecureAppleNonceGenerator: AppleNonceGenerating {
  private static let characters = Array(
    "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._"
  )
  private static let nonceLength = 32

  func makeContext() throws -> AppleAuthorizationRequestContext {
    let rawNonce = try makeRawNonce()
    let digest = SHA256.hash(data: Data(rawNonce.utf8))
    let hashedNonce = digest.map { String(format: "%02x", $0) }.joined()

    return AppleAuthorizationRequestContext(
      rawNonce: rawNonce,
      hashedNonce: hashedNonce
    )
  }

  private func makeRawNonce() throws -> String {
    let upperBound = UInt8.max
      - UInt8.max % UInt8(Self.characters.count)
    var result = ""
    result.reserveCapacity(Self.nonceLength)

    while result.count < Self.nonceLength {
      var bytes = [UInt8](
        repeating: 0,
        count: Self.nonceLength - result.count
      )
      let status = bytes.withUnsafeMutableBytes { buffer in
        SecRandomCopyBytes(
          kSecRandomDefault,
          buffer.count,
          buffer.baseAddress!
        )
      }
      guard status == errSecSuccess else {
        throw AppleNonceGenerationError.randomBytes(status)
      }

      for byte in bytes where byte < upperBound {
        result.append(
          Self.characters[Int(byte) % Self.characters.count]
        )
        if result.count == Self.nonceLength {
          break
        }
      }
    }

    return result
  }
}

@MainActor
final class AppleAuthorizationSession {
  private let nonceGenerator: any AppleNonceGenerating
  private let adapter: AppleAuthorizationAdapter
  private let failureReporter: any AppleAuthorizationFailureReporting
  private var requestContext: AppleAuthorizationRequestContext?

  init(
    nonceGenerator: any AppleNonceGenerating = SecureAppleNonceGenerator(),
    adapter: AppleAuthorizationAdapter? = nil,
    failureReporter: any AppleAuthorizationFailureReporting =
      AppleAuthorizationFailureLogger()
  ) {
    self.nonceGenerator = nonceGenerator
    self.adapter = adapter ?? AppleAuthorizationAdapter(
      failureReporter: failureReporter
    )
    self.failureReporter = failureReporter
  }

  @discardableResult
  func configure(_ request: ASAuthorizationAppleIDRequest) -> Bool {
    request.requestedScopes = []

    do {
      let context = try nonceGenerator.makeContext()
      requestContext = context
      request.nonce = context.hashedNonce
      return true
    } catch {
      requestContext = nil
      request.nonce = nil
      return false
    }
  }

  func outcome(
    for result: Result<ASAuthorization, Error>
  ) -> SocialAuthorizationOutcome {
    guard let requestContext else {
      failureReporter.report(.missingRequestContext)
      return .failed
    }

    self.requestContext = nil
    return adapter.outcome(
      for: result,
      rawNonce: requestContext.rawNonce
    )
  }
}

nonisolated enum AppleCredentialState: Equatable, Sendable {
  case authorized
  case revoked
  case notFound
  case transferred
  case unknown
}

nonisolated protocol AppleCredentialStateProviding: Sendable {
  func credentialState(
    forUserIdentifier userIdentifier: String
  ) async -> AppleCredentialState
}

nonisolated final class SystemAppleCredentialStateProvider:
  AppleCredentialStateProviding,
  @unchecked Sendable {
  private let provider = ASAuthorizationAppleIDProvider()

  func credentialState(
    forUserIdentifier userIdentifier: String
  ) async -> AppleCredentialState {
    await withCheckedContinuation { continuation in
      provider.getCredentialState(forUserID: userIdentifier) { state, error in
        guard error == nil else {
          continuation.resume(returning: .unknown)
          return
        }

        let mappedState: AppleCredentialState
        switch state {
        case .authorized:
          mappedState = .authorized
        case .revoked:
          mappedState = .revoked
        case .notFound:
          mappedState = .notFound
        case .transferred:
          mappedState = .transferred
        @unknown default:
          mappedState = .unknown
        }
        continuation.resume(returning: mappedState)
      }
    }
  }
}

@MainActor
final class AppleCredentialMonitor {
  private let accountSessionStore: AccountSessionStore
  private let stateProvider: any AppleCredentialStateProviding
  private let notificationCenter: NotificationCenter
  private var cancellables: Set<AnyCancellable> = []
  private var validationTask: Task<Void, Never>?

  init(
    accountSessionStore: AccountSessionStore,
    stateProvider: any AppleCredentialStateProviding =
      SystemAppleCredentialStateProvider(),
    notificationCenter: NotificationCenter = .default
  ) {
    self.accountSessionStore = accountSessionStore
    self.stateProvider = stateProvider
    self.notificationCenter = notificationCenter
  }

  func start() {
    guard cancellables.isEmpty else {
      return
    }

    accountSessionStore.$state
      .removeDuplicates()
      .sink { [weak self] state in
        Task { @MainActor [weak self] in
          self?.accountSessionStateDidChange(state)
        }
      }
      .store(in: &cancellables)

    notificationCenter.publisher(
      for: ASAuthorizationAppleIDProvider.credentialRevokedNotification
    )
    .sink { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.scheduleValidation()
      }
    }
    .store(in: &cancellables)
  }

  func validateCurrentAccount() async {
    guard case .signedIn(let account) = accountSessionStore.state,
          account.provider == .apple,
          let userIdentifier = normalized(account.providerUserIdentifier) else {
      return
    }

    let state = await stateProvider.credentialState(
      forUserIdentifier: userIdentifier
    )
    guard shouldInvalidateSession(for: state),
          case .signedIn(let currentAccount) = accountSessionStore.state,
          currentAccount.provider == .apple,
          normalized(currentAccount.providerUserIdentifier)
            == userIdentifier else {
      return
    }

    try? accountSessionStore.removeLocalAccountSession()
  }

  private func accountSessionStateDidChange(_ state: AccountSessionState) {
    guard case .signedIn(let account) = state,
          account.provider == .apple,
          normalized(account.providerUserIdentifier) != nil else {
      validationTask?.cancel()
      validationTask = nil
      return
    }

    scheduleValidation()
  }

  private func scheduleValidation() {
    validationTask?.cancel()
    validationTask = Task { @MainActor [weak self] in
      await self?.validateCurrentAccount()
    }
  }

  private func shouldInvalidateSession(
    for state: AppleCredentialState
  ) -> Bool {
    switch state {
    case .revoked, .notFound, .transferred:
      true
    case .authorized, .unknown:
      false
    }
  }

  private func normalized(_ value: String?) -> String? {
    guard let value else {
      return nil
    }

    let normalizedValue = value.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    return normalizedValue.isEmpty ? nil : normalizedValue
  }
}
