//
//  KakaoSignInSession.swift
//  Moru
//

import Foundation

import KakaoSDKAuth
import KakaoSDKCommon
import KakaoSDKUser

nonisolated struct KakaoSignInPublicConfiguration: Equatable, Sendable {
  let nativeAppKey: String
  let urlScheme: String

  init?(nativeAppKey: String?, urlScheme: String?) {
    guard let nativeAppKey = Self.normalized(nativeAppKey),
          let urlScheme = Self.normalized(urlScheme),
          nativeAppKey.count == 32,
          nativeAppKey.unicodeScalars.allSatisfy(
            CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains
          ),
          urlScheme.caseInsensitiveCompare("kakao\(nativeAppKey)")
            == .orderedSame else {
      return nil
    }

    self.nativeAppKey = nativeAppKey
    self.urlScheme = urlScheme
  }

  private static func normalized(_ value: String?) -> String? {
    guard let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !normalized.isEmpty else {
      return nil
    }

    return normalized
  }
}

nonisolated struct KakaoAuthorizationAdapter {
  func outcome(accessToken: String?) -> SocialAuthorizationOutcome {
    guard let accessToken = accessToken?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !accessToken.isEmpty else {
      return .failed
    }

    return .authorized(
      SocialAuthorization(
        provider: .kakao,
        token: accessToken
      )
    )
  }

  func outcome(error: Error) -> SocialAuthorizationOutcome {
    guard let sdkError = error as? SdkError,
          sdkError.isClientFailed,
          sdkError.getClientError().reason == .Cancelled else {
      return .failed
    }

    return .cancelled
  }
}

@MainActor
protocol KakaoUserAPIClient: AnyObject {
  var isKakaoTalkLoginAvailable: Bool { get }
  func loginWithKakaoTalk(
    completion: @escaping (String?, Error?) -> Void
  )
  func loginWithKakaoAccount(
    completion: @escaping (String?, Error?) -> Void
  )
  func logout(completion: @escaping (Error?) -> Void)
  func unlink(completion: @escaping (Error?) -> Void)
}

@MainActor
final class DefaultKakaoUserAPIClient: KakaoUserAPIClient {
  var isKakaoTalkLoginAvailable: Bool {
    UserApi.isKakaoTalkLoginAvailable()
  }

  func loginWithKakaoTalk(
    completion: @escaping (String?, Error?) -> Void
  ) {
    UserApi.shared.loginWithKakaoTalk { token, error in
      completion(token?.accessToken, error)
    }
  }

  func loginWithKakaoAccount(
    completion: @escaping (String?, Error?) -> Void
  ) {
    UserApi.shared.loginWithKakaoAccount { token, error in
      completion(token?.accessToken, error)
    }
  }

  func logout(completion: @escaping (Error?) -> Void) {
    UserApi.shared.logout(completion: completion)
  }

  func unlink(completion: @escaping (Error?) -> Void) {
    UserApi.shared.unlink(completion: completion)
  }
}

@MainActor
protocol KakaoAuthorizationStarting: AnyObject {
  var isConfigured: Bool { get }
  func authorize() async -> SocialAuthorizationOutcome
}

@MainActor
final class KakaoSignInSession:
  KakaoAuthorizationStarting,
  AuthCallbackHandling,
  SocialProviderSessionSigningOut {
  typealias SDKInitializer = @MainActor (String) -> Void

  private let configuration: KakaoSignInPublicConfiguration?
  private let adapter: KakaoAuthorizationAdapter
  private let userAPIClient: (any KakaoUserAPIClient)?

  var isConfigured: Bool {
    configuration != nil && userAPIClient != nil
  }

  init(
    configuration: SocialLoginPublicConfiguration,
    adapter: KakaoAuthorizationAdapter = KakaoAuthorizationAdapter(),
    userAPIClient: (any KakaoUserAPIClient)? = nil,
    initializeSDK: SDKInitializer = {
      KakaoSDK.initSDK(appKey: $0)
    }
  ) {
    self.configuration = configuration.kakaoSignInConfiguration
    self.adapter = adapter

    guard let kakaoConfiguration = self.configuration else {
      self.userAPIClient = nil
      return
    }

    initializeSDK(kakaoConfiguration.nativeAppKey)
    self.userAPIClient = userAPIClient ?? DefaultKakaoUserAPIClient()
  }

  func authorize() async -> SocialAuthorizationOutcome {
    guard let userAPIClient else {
      return .failed
    }

    return await withCheckedContinuation { continuation in
      let completion: (String?, Error?) -> Void = { [adapter] token, error in
        if let error {
          continuation.resume(returning: adapter.outcome(error: error))
        } else {
          continuation.resume(returning: adapter.outcome(accessToken: token))
        }
      }

      if userAPIClient.isKakaoTalkLoginAvailable {
        userAPIClient.loginWithKakaoTalk(completion: completion)
      } else {
        userAPIClient.loginWithKakaoAccount(completion: completion)
      }
    }
  }

  func handleAuthCallback(_ url: URL) -> Bool {
    guard isConfigured, AuthApi.isKakaoTalkLoginUrl(url) else {
      return false
    }

    return AuthController.handleOpenUrl(url: url)
  }

  func signOut(
    provider: AuthProvider,
    reason: SocialProviderSessionSignOutReason
  ) async throws {
    guard provider == .kakao, let userAPIClient else {
      return
    }

    switch reason {
    case .logout:
      _ = await withCheckedContinuation { continuation in
        userAPIClient.logout { error in
          continuation.resume(returning: error)
        }
      }
    case .withdrawal:
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        userAPIClient.unlink { error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume()
          }
        }
      }
    }
  }
}

@MainActor
final class UnavailableKakaoAuthorizationSession: KakaoAuthorizationStarting {
  var isConfigured: Bool {
    false
  }

  func authorize() async -> SocialAuthorizationOutcome {
    .failed
  }
}
