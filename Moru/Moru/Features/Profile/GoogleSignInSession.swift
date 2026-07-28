//
//  GoogleSignInSession.swift
//  Moru
//

import Foundation
import UIKit

import GoogleSignIn

nonisolated struct GoogleSignInPublicConfiguration: Equatable, Sendable {
  let clientID: String
  let serverClientID: String
  let reversedClientID: String

  init?(
    clientID: String?,
    serverClientID: String?,
    reversedClientID: String?
  ) {
    guard let clientID = Self.normalized(clientID),
          let serverClientID = Self.normalized(serverClientID),
          let reversedClientID = Self.normalized(reversedClientID),
          clientID.hasSuffix(".apps.googleusercontent.com"),
          serverClientID.hasSuffix(".apps.googleusercontent.com"),
          reversedClientID == Self.reversed(clientID) else {
      return nil
    }

    self.clientID = clientID
    self.serverClientID = serverClientID
    self.reversedClientID = reversedClientID
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value else {
      return nil
    }

    let normalizedValue = value.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    return normalizedValue.isEmpty ? nil : normalizedValue
  }

  private static func reversed(_ clientID: String) -> String {
    clientID
      .split(separator: ".")
      .reversed()
      .joined(separator: ".")
  }
}

nonisolated struct GoogleAuthorizationAdapter {
  static let cancellationErrorDomain = kGIDSignInErrorDomain
  // GoogleSignIn 9.1.0 declares kGIDSignInErrorCodeCanceled as -5.
  static let cancellationErrorCode = -5

  func outcome(idToken: String?) -> SocialAuthorizationOutcome {
    guard let idToken = idToken?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !idToken.isEmpty else {
      return .failed
    }

    return .authorized(
      SocialAuthorization(
        provider: .google,
        token: idToken
      )
    )
  }

  func outcome(error: Error) -> SocialAuthorizationOutcome {
    let nsError = error as NSError
    guard nsError.domain == Self.cancellationErrorDomain,
          nsError.code == Self.cancellationErrorCode else {
      return .failed
    }

    return .cancelled
  }
}

@MainActor
protocol GoogleAuthorizationStarting: AnyObject {
  var isConfigured: Bool { get }
  func authorize() async -> SocialAuthorizationOutcome
}

@MainActor
final class GoogleSignInSession:
  GoogleAuthorizationStarting,
  AuthCallbackHandling,
  SocialProviderSessionSigningOut {
  typealias PresenterProvider = @MainActor () -> UIViewController?

  private let configuration: GoogleSignInPublicConfiguration?
  private let adapter: GoogleAuthorizationAdapter
  private let presenterProvider: PresenterProvider

  var isConfigured: Bool {
    configuration != nil
  }

  init(
    configuration: SocialLoginPublicConfiguration,
    adapter: GoogleAuthorizationAdapter = GoogleAuthorizationAdapter(),
    presenterProvider: @escaping PresenterProvider = {
      GoogleSignInSession.topViewController()
    }
  ) {
    self.configuration = configuration.googleSignInConfiguration
    self.adapter = adapter
    self.presenterProvider = presenterProvider

    if let configuration = self.configuration {
      GIDSignIn.sharedInstance.configuration = GIDConfiguration(
        clientID: configuration.clientID,
        serverClientID: configuration.serverClientID
      )
    }
  }

  func authorize() async -> SocialAuthorizationOutcome {
    guard configuration != nil,
          let presenter = presenterProvider() else {
      return .failed
    }

    do {
      let result = try await GIDSignIn.sharedInstance.signIn(
        withPresenting: presenter
      )
      let refreshedUser = try await result.user.refreshTokensIfNeeded()
      return adapter.outcome(idToken: refreshedUser.idToken?.tokenString)
    } catch {
      return adapter.outcome(error: error)
    }
  }

  func handleAuthCallback(_ url: URL) -> Bool {
    guard configuration != nil else {
      return false
    }

    return GIDSignIn.sharedInstance.handle(url)
  }

  func signOut(provider: AuthProvider) {
    guard provider == .google else {
      return
    }

    GIDSignIn.sharedInstance.signOut()
  }

  private static func topViewController() -> UIViewController? {
    let rootViewController = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController

    return topViewController(from: rootViewController)
  }

  private static func topViewController(
    from viewController: UIViewController?
  ) -> UIViewController? {
    if let presented = viewController?.presentedViewController {
      return topViewController(from: presented)
    }
    if let navigationController = viewController as? UINavigationController {
      return topViewController(
        from: navigationController.visibleViewController
      )
    }
    if let tabBarController = viewController as? UITabBarController {
      return topViewController(
        from: tabBarController.selectedViewController
      )
    }

    return viewController
  }
}

@MainActor
final class UnavailableGoogleAuthorizationSession: GoogleAuthorizationStarting {
  var isConfigured: Bool {
    false
  }

  func authorize() async -> SocialAuthorizationOutcome {
    .failed
  }
}
