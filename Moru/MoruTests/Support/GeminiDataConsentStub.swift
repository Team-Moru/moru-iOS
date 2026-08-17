//
//  GeminiDataConsentStub.swift
//  MoruTests
//

@testable import Moru

@MainActor
final class GeminiDataConsentStub: GeminiDataConsentAuthorizing {
  var hasExplicitGeminiDataConsent: Bool
  private(set) var requestCount = 0

  init(hasExplicitGeminiDataConsent: Bool = true) {
    self.hasExplicitGeminiDataConsent = hasExplicitGeminiDataConsent
  }

  func requestGeminiDataConsentIfNeeded() {
    requestCount += 1
  }
}
