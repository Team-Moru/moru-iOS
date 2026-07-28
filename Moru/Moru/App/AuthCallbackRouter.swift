//
//  AuthCallbackRouter.swift
//  Moru
//

import Foundation

nonisolated struct SocialLoginPublicConfiguration: Equatable, Sendable {
  static let googleClientIDInfoKey = "MoruGoogleClientID"
  static let googleServerClientIDInfoKey = "MoruGoogleServerClientID"
  static let googleReversedClientIDInfoKey = "MoruGoogleReversedClientID"
  static let kakaoNativeAppKeyInfoKey = "MoruKakaoNativeAppKey"
  static let googleClientIDPlaceholder = "MORU_GOOGLE_IOS_CLIENT_ID_REQUIRED"
  static let googleServerClientIDPlaceholder =
    "MORU_GOOGLE_SERVER_CLIENT_ID_REQUIRED"
  static let googleReversedClientIDPlaceholder =
    "moru-google-reversed-client-id-required"

  let googleClientID: String?
  let googleServerClientID: String?
  let googleReversedClientID: String?
  let kakaoNativeAppKey: String?

  init(
    googleClientID: String? = nil,
    googleServerClientID: String? = nil,
    googleReversedClientID: String? = nil,
    kakaoNativeAppKey: String? = nil
  ) {
    self.googleClientID = Self.normalized(googleClientID)
    self.googleServerClientID = Self.normalized(googleServerClientID)
    self.googleReversedClientID = Self.normalized(googleReversedClientID)
    self.kakaoNativeAppKey = Self.normalized(kakaoNativeAppKey)
  }

  init(infoDictionary: [String: Any]) {
    self.init(
      googleClientID: infoDictionary[Self.googleClientIDInfoKey] as? String,
      googleServerClientID:
        infoDictionary[Self.googleServerClientIDInfoKey] as? String,
      googleReversedClientID:
        infoDictionary[Self.googleReversedClientIDInfoKey] as? String,
      kakaoNativeAppKey:
        infoDictionary[Self.kakaoNativeAppKeyInfoKey] as? String
    )
  }

  static let mainBundle = SocialLoginPublicConfiguration(
    infoDictionary: Bundle.main.infoDictionary ?? [:]
  )

  var googleSignInConfiguration: GoogleSignInPublicConfiguration? {
    GoogleSignInPublicConfiguration(
      clientID: googleClientID,
      serverClientID: googleServerClientID,
      reversedClientID: googleReversedClientID
    )
  }

  func provider(forCallbackURL url: URL) -> AuthProvider? {
    guard let scheme = Self.normalized(url.scheme) else {
      return nil
    }

    if let googleReversedClientID,
       scheme.caseInsensitiveCompare(googleReversedClientID) == .orderedSame {
      return .google
    }

    if let kakaoNativeAppKey,
       scheme.caseInsensitiveCompare("kakao\(kakaoNativeAppKey)") == .orderedSame {
      return .kakao
    }

    return nil
  }

  nonisolated private static func normalized(_ value: String?) -> String? {
    guard let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !normalized.isEmpty,
      !normalized.contains("$("),
      ![
        googleClientIDPlaceholder,
        googleServerClientIDPlaceholder,
        googleReversedClientIDPlaceholder,
      ].contains(normalized) else {
      return nil
    }

    return normalized
  }
}
@MainActor
protocol AuthCallbackHandling: AnyObject {
  func handleAuthCallback(_ url: URL) -> Bool
}

@MainActor
final class AuthCallbackRouter {
  private let configuration: SocialLoginPublicConfiguration
  private var handlers: [AuthProvider: any AuthCallbackHandling] = [:]

  init(configuration: SocialLoginPublicConfiguration) {
    self.configuration = configuration
  }

  func register(
    _ handler: any AuthCallbackHandling,
    for provider: AuthProvider
  ) {
    guard Self.supportsCallback(provider) else {
      return
    }

    handlers[provider] = handler
  }

  @discardableResult
  func route(_ url: URL) -> Bool {
    guard let provider = configuration.provider(forCallbackURL: url),
          let handler = handlers[provider] else {
      return false
    }

    return handler.handleAuthCallback(url)
  }

  nonisolated private static func supportsCallback(
    _ provider: AuthProvider
  ) -> Bool {
    switch provider {
    case .google, .kakao:
      true
    case .apple, .unknown:
      false
    }
  }
}
