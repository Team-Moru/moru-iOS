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

/// The outcome for one consent-gated request. `.deferred` deliberately does
/// not change the persisted consent status: the caller must keep its input
/// and wait for an explicit retry after the user has made a choice.
nonisolated enum GeminiDataConsentDecision: Equatable, Sendable {
  case granted
  case declined
  case deferred
}

@MainActor
protocol GeminiDataConsentAuthorizing: AnyObject {
  /// The full choice is needed by flows that must hold an AI request until
  /// the user decides, rather than silently producing a local result.
  var geminiDataConsentStatus: GeminiDataConsentStatus { get }
  var hasExplicitGeminiDataConsent: Bool { get }

  /// Requests a disclosure only while the user has not yet made a choice.
  /// A previous refusal must not repeatedly surface a modal from a background
  /// Outbox wake-up.
  func requestGeminiDataConsentIfNeeded()

  /// Suspends a consent-gated request while the choice is undecided. It
  /// returns immediately once the user has already granted, declined, or
  /// dismissed the current choice sheet for later.
  func waitForGeminiDataConsentDecision()
    async throws -> GeminiDataConsentDecision
}

/// Keeps cancellation and consent changes race-safe for the requests that
/// are intentionally held while the disclosure sheet is visible.
@MainActor
final class GeminiDataConsentDecisionGate {
  private var status: GeminiDataConsentStatus
  private var waiters: [
    UUID: CheckedContinuation<GeminiDataConsentDecision, Error>
  ] = [:]
  private var cancelledWaiterIDs = Set<UUID>()

  init(status: GeminiDataConsentStatus) {
    self.status = status
  }

  func waitForDecision() async throws -> GeminiDataConsentDecision {
    if let decision = finalizedDecision(for: status) {
      return decision
    }

    let waiterID = UUID()
    return try await withTaskCancellationHandler(
      operation: {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation {
          (
            continuation: CheckedContinuation<GeminiDataConsentDecision, Error>
          ) in
          if let decision = finalizedDecision(for: status) {
            continuation.resume(returning: decision)
          } else if cancelledWaiterIDs.remove(waiterID) != nil {
            continuation.resume(throwing: CancellationError())
          } else {
            waiters[waiterID] = continuation
          }
        }
      },
      onCancel: {
        Task { @MainActor [weak self] in
          self?.cancelWaiter(id: waiterID)
        }
      }
    )
  }

  func update(_ nextStatus: GeminiDataConsentStatus) {
    status = nextStatus
    guard let decision = finalizedDecision(for: nextStatus) else {
      return
    }

    let pendingWaiters = Array(waiters.values)
    waiters.removeAll()
    cancelledWaiterIDs.removeAll()
    for waiter in pendingWaiters {
      waiter.resume(returning: decision)
    }
  }

  /// Releases all currently held requests without interpreting dismissal as a
  /// refusal. The status remains `.undecided`, so a later user retry presents
  /// the disclosure again instead of using a local fallback.
  func deferDecision() {
    guard status == .undecided else {
      return
    }

    let pendingWaiters = Array(waiters.values)
    waiters.removeAll()
    cancelledWaiterIDs.removeAll()
    for waiter in pendingWaiters {
      waiter.resume(returning: .deferred)
    }
  }

  private func cancelWaiter(id: UUID) {
    if let waiter = waiters.removeValue(forKey: id) {
      waiter.resume(throwing: CancellationError())
    } else if status == .undecided {
      // Cancellation can arrive just before the continuation is registered.
      // Remember it so the registration path resumes immediately instead of
      // retaining a request that has already disappeared.
      cancelledWaiterIDs.insert(id)
    }
  }

  private func finalizedDecision(
    for status: GeminiDataConsentStatus
  ) -> GeminiDataConsentDecision? {
    switch status {
    case .undecided:
      nil
    case .granted:
      .granted
    case .declined:
      .declined
    }
  }
}

/// Versioned consent for AI features whose server processing may
/// send user routine content to Google Gemini.
@MainActor
final class GeminiDataConsentStore: ObservableObject,
  GeminiDataConsentAuthorizing {
  static let disclosureVersion = "2026-08-17-google-free-tier"
  /// Bumping the disclosure version deliberately starts from `.undecided`, so
  /// an old approval is never silently reused for a materially new notice.
  static let defaultStorageKey =
    "moru.gemini-data-consent.\(disclosureVersion)"

  @Published private(set) var status: GeminiDataConsentStatus
  @Published private(set) var isConsentPresentationRequested = false

  private let defaults: UserDefaults
  private let storageKey: String
  private let decisionGate: GeminiDataConsentDecisionGate

  var geminiDataConsentStatus: GeminiDataConsentStatus {
    status
  }

  var hasExplicitGeminiDataConsent: Bool {
    status == .granted
  }

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = GeminiDataConsentStore.defaultStorageKey
  ) {
    self.defaults = defaults
    self.storageKey = storageKey

    let initialStatus: GeminiDataConsentStatus
    if let stored = defaults.string(forKey: storageKey),
       let decoded = GeminiDataConsentStatus(rawValue: stored) {
      initialStatus = decoded
    } else {
      initialStatus = .undecided
    }
    status = initialStatus
    decisionGate = GeminiDataConsentDecisionGate(status: initialStatus)
  }

  func requestGeminiDataConsentIfNeeded() {
    guard status == .undecided else {
      return
    }
    isConsentPresentationRequested = true
  }

  func waitForGeminiDataConsentDecision()
    async throws -> GeminiDataConsentDecision {
    switch status {
    case .granted:
      return .granted
    case .declined:
      return .declined
    case .undecided:
      break
    }

    // A dismissal can happen between requesting the sheet and registering the
    // actor continuation. Treat that exact request as deferred rather than
    // leaving it suspended forever; a subsequent retry will request the sheet
    // again before calling this method.
    guard isConsentPresentationRequested else {
      return .deferred
    }

    return try await decisionGate.waitForDecision()
  }

  /// Opens the disclosure from a user-initiated setting even after a prior
  /// refusal, so consent can be granted later without recreating data.
  func presentConsentChoices() {
    isConsentPresentationRequested = true
  }

  func dismissConsentChoices() {
    isConsentPresentationRequested = false
    guard status == .undecided else {
      return
    }

    decisionGate.deferDecision()
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
    decisionGate.update(nextStatus)
  }
}

@MainActor
final class UnavailableGeminiDataConsentAuthorizer:
  GeminiDataConsentAuthorizing {
  var geminiDataConsentStatus: GeminiDataConsentStatus { .declined }
  var hasExplicitGeminiDataConsent: Bool { false }

  func requestGeminiDataConsentIfNeeded() {}

  func waitForGeminiDataConsentDecision()
    async throws -> GeminiDataConsentDecision {
    .declined
  }
}
