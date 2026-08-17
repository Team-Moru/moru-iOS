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
}
