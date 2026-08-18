//
//  GeminiDataConsentStoreTests.swift
//  MoruTests
//

import Foundation
import XCTest
@testable import Moru

@MainActor
final class GeminiDataConsentStoreTests: XCTestCase {
  func testDeclineIsPersistedAndDoesNotRepeatedlyPresentFromBackgroundWork() {
    let suiteName = "GeminiDataConsentStoreTests.\(UUID().uuidString)"
    let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let storageKey = "gemini-consent"
    let store = GeminiDataConsentStore(
      defaults: defaults,
      storageKey: storageKey
    )

    XCTAssertEqual(store.status, .undecided)
    XCTAssertFalse(store.hasExplicitGeminiDataConsent)
    XCTAssertFalse(store.isConsentPresentationRequested)

    store.requestGeminiDataConsentIfNeeded()
    XCTAssertTrue(store.isConsentPresentationRequested)

    store.decline()
    XCTAssertEqual(store.status, .declined)
    XCTAssertFalse(store.hasExplicitGeminiDataConsent)
    XCTAssertFalse(store.isConsentPresentationRequested)

    store.requestGeminiDataConsentIfNeeded()
    XCTAssertFalse(store.isConsentPresentationRequested)

    let restored = GeminiDataConsentStore(
      defaults: defaults,
      storageKey: storageKey
    )
    XCTAssertEqual(restored.status, .declined)
    restored.presentConsentChoices()
    XCTAssertTrue(restored.isConsentPresentationRequested)
    restored.grant()

    XCTAssertEqual(restored.status, .granted)
    XCTAssertTrue(restored.hasExplicitGeminiDataConsent)
    XCTAssertFalse(restored.isConsentPresentationRequested)

    restored.revoke()
    XCTAssertEqual(restored.status, .declined)
    XCTAssertFalse(restored.hasExplicitGeminiDataConsent)
  }

  func testDefaultStorageKeyIsScopedToDisclosureVersion() {
    XCTAssertTrue(
      GeminiDataConsentStore.defaultStorageKey.contains(
        GeminiDataConsentStore.disclosureVersion
      )
    )
  }

  func testUndecidedRequestWaitsForDecisionThenResumesWithGrantedStatus()
    async throws {
    let suiteName = "GeminiDataConsentStoreTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = GeminiDataConsentStore(
      defaults: defaults,
      storageKey: "gemini-consent"
    )
    store.requestGeminiDataConsentIfNeeded()
    let task = _Concurrency.Task {
      try await store.waitForGeminiDataConsentDecision()
    }

    await _Concurrency.Task<Never, Never>.yield()
    store.grant()

    let decision = try await task.value
    XCTAssertEqual(decision, .granted)
  }

  func testUndecidedRequestDismissalResumesAsDeferredWithoutPersistingChoice()
    async throws {
    let suiteName = "GeminiDataConsentStoreTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = GeminiDataConsentStore(
      defaults: defaults,
      storageKey: "gemini-consent"
    )
    store.requestGeminiDataConsentIfNeeded()
    let task = _Concurrency.Task {
      try await store.waitForGeminiDataConsentDecision()
    }

    store.dismissConsentChoices()

    let decision = try await task.value
    XCTAssertEqual(decision, .deferred)
    XCTAssertEqual(store.status, .undecided)
    XCTAssertFalse(store.isConsentPresentationRequested)
  }

  func testMaterialDisclosureChangeDoesNotReusePreviousApproval() {
    let suiteName = "GeminiDataConsentStoreTests.\(UUID().uuidString)"
    let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set(
      GeminiDataConsentStatus.granted.rawValue,
      forKey: "moru.gemini-data-consent.2026-08-17-tts"
    )

    let store = GeminiDataConsentStore(defaults: defaults)

    XCTAssertEqual(store.status, .undecided)
    XCTAssertFalse(store.hasExplicitGeminiDataConsent)
  }
}
