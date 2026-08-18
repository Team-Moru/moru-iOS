//
//  GeminiDataConsentStub.swift
//  MoruTests
//

@testable import Moru

@MainActor
final class GeminiDataConsentStub: GeminiDataConsentAuthorizing {
  var geminiDataConsentStatus: GeminiDataConsentStatus {
    didSet {
      let nextStatus = geminiDataConsentStatus
      decisionGate.update(nextStatus)
    }
  }
  var hasExplicitGeminiDataConsent: Bool {
    get {
      geminiDataConsentStatus == .granted
    }
    set {
      geminiDataConsentStatus = newValue ? .granted : .declined
    }
  }
  private(set) var requestCount = 0
  private var isConsentPresentationRequested = false
  private let decisionGate: GeminiDataConsentDecisionGate

  init(hasExplicitGeminiDataConsent: Bool = true) {
    let initialStatus: GeminiDataConsentStatus = hasExplicitGeminiDataConsent
      ? .granted
      : .declined
    geminiDataConsentStatus = initialStatus
    decisionGate = GeminiDataConsentDecisionGate(status: initialStatus)
  }

  init(status: GeminiDataConsentStatus) {
    geminiDataConsentStatus = status
    decisionGate = GeminiDataConsentDecisionGate(status: status)
  }

  func requestGeminiDataConsentIfNeeded() {
    guard geminiDataConsentStatus == .undecided else {
      return
    }
    requestCount += 1
    isConsentPresentationRequested = true
  }

  func waitForGeminiDataConsentDecision()
    async throws -> GeminiDataConsentDecision {
    switch geminiDataConsentStatus {
    case .granted:
      return .granted
    case .declined:
      return .declined
    case .undecided:
      break
    }

    guard isConsentPresentationRequested else {
      return .deferred
    }

    return try await decisionGate.waitForDecision()
  }

  func grant() {
    geminiDataConsentStatus = .granted
    isConsentPresentationRequested = false
  }

  func decline() {
    geminiDataConsentStatus = .declined
    isConsentPresentationRequested = false
  }

  func dismissConsentChoices() {
    isConsentPresentationRequested = false
    decisionGate.deferDecision()
  }
}
