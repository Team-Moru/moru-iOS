//
//  GeminiDataConsentStore.swift
//  Moru
//

import Combine
import Foundation

/// The user-controlled state for data that may be sent to Google Gemini.
///
/// This is deliberately independent of account login. A signed-in account is
/// never evidence of consent to send routine content to an external AI
/// provider.
nonisolated enum GeminiDataConsentStatus: String, Codable, Equatable, Sendable {
  case undecided
  case granted
  case declined
}

@MainActor
protocol GeminiDataConsentAuthorizing: AnyObject {
  var hasExplicitGeminiDataConsent: Bool { get }

  /// Requests a disclosure only while the user has not yet made a choice.
  /// A previous refusal must not repeatedly surface a modal from a background
  /// Outbox wake-up.
  func requestGeminiDataConsentIfNeeded()
}

/// Persisted, versioned consent for AI features whose server processing may
/// send user routine content to Google Gemini.
@MainActor
final class GeminiDataConsentStore: ObservableObject,
  GeminiDataConsentAuthorizing {
  static let disclosureVersion = "2026-08-17-tts"
  /// Bumping the disclosure version deliberately starts from `.undecided`, so
  /// an old approval is never silently reused for a materially new notice.
  static let defaultStorageKey =
    "moru.gemini-data-consent.\(disclosureVersion)"

  @Published private(set) var status: GeminiDataConsentStatus
  @Published private(set) var isConsentPresentationRequested = false

  private let defaults: UserDefaults
  private let storageKey: String

  var hasExplicitGeminiDataConsent: Bool {
    status == .granted
  }

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = GeminiDataConsentStore.defaultStorageKey
  ) {
    self.defaults = defaults
    self.storageKey = storageKey

    guard let stored = defaults.string(forKey: storageKey),
          let decoded = GeminiDataConsentStatus(rawValue: stored) else {
      status = .undecided
      return
    }
    status = decoded
  }

  func requestGeminiDataConsentIfNeeded() {
    guard status == .undecided else {
      return
    }
    isConsentPresentationRequested = true
  }

  /// Opens the disclosure from a user-initiated setting even after a prior
  /// refusal, so consent can be granted later without recreating data.
  func presentConsentChoices() {
    isConsentPresentationRequested = true
  }

  func dismissConsentChoices() {
    isConsentPresentationRequested = false
  }

  func grant() {
    save(.granted)
    isConsentPresentationRequested = false
  }

  func decline() {
    save(.declined)
    isConsentPresentationRequested = false
  }

  func revoke() {
    save(.declined)
  }

  private func save(_ nextStatus: GeminiDataConsentStatus) {
    status = nextStatus
    defaults.set(nextStatus.rawValue, forKey: storageKey)
  }
}

@MainActor
final class UnavailableGeminiDataConsentAuthorizer:
  GeminiDataConsentAuthorizing {
  var hasExplicitGeminiDataConsent: Bool { false }

  func requestGeminiDataConsentIfNeeded() {}
}
