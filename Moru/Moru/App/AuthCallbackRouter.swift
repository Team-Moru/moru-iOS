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
  static let kakaoURLSchemeInfoKey = "MoruKakaoURLScheme"
  static let googleClientIDPlaceholder = "MORU_GOOGLE_IOS_CLIENT_ID_REQUIRED"
  static let googleServerClientIDPlaceholder =
    "MORU_GOOGLE_SERVER_CLIENT_ID_REQUIRED"
  static let googleReversedClientIDPlaceholder =
    "moru-google-reversed-client-id-required"
  static let kakaoNativeAppKeyPlaceholder =
    "MORU_KAKAO_NATIVE_APP_KEY_REQUIRED"
  static let kakaoURLSchemePlaceholder =
    "moru-kakao-url-scheme-required"

  let googleClientID: String?
  let googleServerClientID: String?
  let googleReversedClientID: String?
  let kakaoNativeAppKey: String?
  let kakaoURLScheme: String?

  init(
    googleClientID: String? = nil,
    googleServerClientID: String? = nil,
    googleReversedClientID: String? = nil,
    kakaoNativeAppKey: String? = nil,
    kakaoURLScheme: String? = nil
  ) {
    self.googleClientID = Self.normalized(googleClientID)
    self.googleServerClientID = Self.normalized(googleServerClientID)
    self.googleReversedClientID = Self.normalized(googleReversedClientID)
    self.kakaoNativeAppKey = Self.normalized(kakaoNativeAppKey)
    self.kakaoURLScheme = Self.normalized(kakaoURLScheme)
  }

  init(infoDictionary: [String: Any]) {
    self.init(
      googleClientID: infoDictionary[Self.googleClientIDInfoKey] as? String,
      googleServerClientID:
        infoDictionary[Self.googleServerClientIDInfoKey] as? String,
      googleReversedClientID:
        infoDictionary[Self.googleReversedClientIDInfoKey] as? String,
      kakaoNativeAppKey:
        infoDictionary[Self.kakaoNativeAppKeyInfoKey] as? String,
      kakaoURLScheme:
        infoDictionary[Self.kakaoURLSchemeInfoKey] as? String
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

  var kakaoSignInConfiguration: KakaoSignInPublicConfiguration? {
    KakaoSignInPublicConfiguration(
      nativeAppKey: kakaoNativeAppKey,
      urlScheme: kakaoURLScheme
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

    if let kakaoSignInConfiguration,
       scheme.caseInsensitiveCompare(kakaoSignInConfiguration.urlScheme)
        == .orderedSame {
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
        kakaoNativeAppKeyPlaceholder,
        kakaoURLSchemePlaceholder,
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
