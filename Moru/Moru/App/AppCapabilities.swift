//
//  AppCapabilities.swift
//  Moru
//

import Foundation

nonisolated struct AppCapabilities: Equatable, Sendable {
  let accountFeaturesEnabled: Bool

  static let production = AppCapabilities(accountFeaturesEnabled: true)
  static let localOnly = AppCapabilities(accountFeaturesEnabled: false)

  var shouldRestoreAccountSession: Bool {
    accountFeaturesEnabled
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
