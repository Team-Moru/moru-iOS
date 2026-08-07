//
//  AppCapabilities.swift
//  Moru
//

import Foundation

nonisolated struct AppCapabilities: Equatable, Sendable {
  let accountFeaturesEnabled: Bool
  let serverRoutineTTSEnabled: Bool

  static let production = AppCapabilities(
    accountFeaturesEnabled: true,
    serverRoutineTTSEnabled: true
  )
  static let localOnly = AppCapabilities(
    accountFeaturesEnabled: false,
    serverRoutineTTSEnabled: false
  )

  var shouldShowAccountUI: Bool {
    accountFeaturesEnabled
  }

  var shouldRestoreAccountSession: Bool {
    accountFeaturesEnabled
  }

  var shouldAllowServerRequests: Bool {
    accountFeaturesEnabled
  }

  var shouldUseServerRoutineTTS: Bool {
    shouldAllowServerRequests && serverRoutineTTSEnabled
  }

  func canUseAccountFeatures(
    sessionState: AccountSessionState
  ) -> Bool {
    guard accountFeaturesEnabled else {
      return false
    }

    if case .signedIn = sessionState {
      return true
    }

    return false
  }
}
