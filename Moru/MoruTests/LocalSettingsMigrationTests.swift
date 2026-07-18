//
//  LocalSettingsMigrationTests.swift
//  MoruTests
//
//  Created by Codex on 7/18/26.
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

final class LocalSettingsMigrationTests: XCTestCase {
  @MainActor
  func testKnownAvailableYunaResolvesWithoutPreservingOriginalRawID() throws {
    let profile = makeProfile(selectedVoiceID: VoiceProfile.yuna.id)
    let fixture = try makeFixture(profile: profile, availableVoiceIDs: [VoiceProfile.yuna.id])

    let settings = try fixture.repository.resolveVoiceSettings(profileID: profile.id)

    XCTAssertEqual(settings.voiceMigrationState, .resolved)
    XCTAssertNil(settings.originalVoiceID)
    XCTAssertEqual(settings.resolvedVoiceID, VoiceProfile.yuna.id)
    XCTAssertNotNil(settings.migrationUpdatedAt)
    XCTAssertEqual(settings.schemaMigrationMarker, .v2Resolved)
    XCTAssertNil(settings.pendingVoiceMigrationNotice)
    XCTAssertEqual(try fixture.repository.fetchProfile()?.selectedVoice.id, VoiceProfile.yuna.id)
  }

  @MainActor
  func testCatalogueOrderPrefersYunaAndAllowsSelectingSora() throws {
    XCTAssertEqual(VoiceProfile.localVoices, [.yuna, .sora])
    XCTAssertEqual(VoiceProfile.yuna.avSpeechVoiceIdentifier, "com.apple.ttsbundle.Yuna-compact")
    XCTAssertEqual(VoiceProfile.sora.avSpeechVoiceIdentifier, "com.apple.ttsbundle.Sora-compact")

    let profile = makeProfile(selectedVoiceID: VoiceProfile.moru.id)
    let fixture = try makeFixture(
      profile: profile,
      availableVoiceIDs: [VoiceProfile.yuna.id, VoiceProfile.sora.id]
    )

    let migrated = try fixture.repository.resolveVoiceSettings(profileID: profile.id)
    XCTAssertEqual(migrated.voiceMigrationState, .fallbackNoticePending)
    XCTAssertEqual(migrated.resolvedVoiceID, VoiceProfile.yuna.id)
    XCTAssertEqual(try fixture.repository.fetchProfile()?.selectedVoice, .yuna)

    let selected = try fixture.repository.selectVoice(
      profileID: profile.id,
      voiceID: VoiceProfile.sora.id
    )
    XCTAssertEqual(selected.voiceMigrationState, .resolved)
    XCTAssertEqual(selected.resolvedVoiceID, VoiceProfile.sora.id)
    XCTAssertEqual(try fixture.repository.fetchProfile()?.selectedVoice, .sora)
  }

  @MainActor
  func testLegacyVoiceFallsBackToSoraWhenYunaIsUnavailable() throws {
    let profile = makeProfile(selectedVoiceID: VoiceProfile.moru.id)
    let fixture = try makeFixture(profile: profile, availableVoiceIDs: [VoiceProfile.sora.id])

    let settings = try fixture.repository.resolveVoiceSettings(profileID: profile.id)

    XCTAssertEqual(settings.voiceMigrationState, .fallbackNoticePending)
    XCTAssertEqual(settings.originalVoiceID, VoiceProfile.moru.id)
    XCTAssertEqual(settings.resolvedVoiceID, VoiceProfile.sora.id)
    XCTAssertEqual(settings.schemaMigrationMarker, .v2Resolved)
    XCTAssertEqual(settings.pendingVoiceMigrationNotice, "사용 가능한 목소리로 변경했어요")
    XCTAssertEqual(try fixture.repository.fetchProfile()?.selectedVoice.id, VoiceProfile.sora.id)
  }

  @MainActor
  func testLegacyVoiceKeepsRawIDWhenNoCatalogueVoiceIsAvailable() throws {
    let legacyVoiceID = "legacy-unavailable-voice"
    let profile = makeProfile(selectedVoiceID: legacyVoiceID)
    let fixture = try makeFixture(profile: profile, availableVoiceIDs: [])

    let settings = try fixture.repository.resolveVoiceSettings(profileID: profile.id)

    XCTAssertEqual(settings.voiceMigrationState, .noFallbackNoticePending)
    XCTAssertEqual(settings.originalVoiceID, legacyVoiceID)
    XCTAssertNil(settings.resolvedVoiceID)
    XCTAssertNotNil(settings.migrationUpdatedAt)
    XCTAssertEqual(settings.schemaMigrationMarker, .v2Unresolved)
    XCTAssertNil(settings.pendingVoiceMigrationNotice)
    XCTAssertEqual(try fixture.repository.fetchProfile()?.selectedVoice.id, legacyVoiceID)
  }

  @MainActor
  func testCorruptSettingsRepairThenRetryAndAcknowledgePreservesFallbackValues() throws {
    let rawVoiceID = "legacy-corrupt-voice"
    let profile = makeProfile(selectedVoiceID: rawVoiceID)
    let fixture = try makeFixture(profile: profile, availableVoiceIDs: [VoiceProfile.sora.id])
    let context = fixture.container.mainContext
    let corrupt = PersistedLocalSettings(
      id: profile.id,
      profileID: profile.id,
      voiceMigrationStateRawValue: VoiceMigrationState.resolved.rawValue,
      voiceMigrationOriginalVoiceID: rawVoiceID,
      voiceMigrationResolvedVoiceID: VoiceProfile.yuna.id,
      voiceMigrationUpdatedAt: fixture.now,
      schemaMigrationMarkerRawValue: SchemaMigrationMarker.v2Resolved.rawValue
    )
    context.insert(corrupt)
    try context.save()

    let repaired = try XCTUnwrap(try fixture.repository.fetchSettings(profileID: profile.id))
    XCTAssertEqual(repaired.voiceMigrationState, .corruptRecoveryPending)
    XCTAssertEqual(repaired.originalVoiceID, rawVoiceID)
    XCTAssertNil(repaired.resolvedVoiceID)
    XCTAssertEqual(repaired.schemaMigrationMarker, .v2Unresolved)

    let retried = try fixture.repository.resolveVoiceSettings(profileID: profile.id)
    XCTAssertEqual(retried.voiceMigrationState, .fallbackNoticePending)
    XCTAssertEqual(retried.originalVoiceID, rawVoiceID)
    XCTAssertEqual(retried.resolvedVoiceID, VoiceProfile.sora.id)

    try fixture.repository.acknowledgeVoiceNotice(profileID: profile.id)
    let acknowledged = try XCTUnwrap(try fixture.repository.fetchSettings(profileID: profile.id))
    XCTAssertEqual(acknowledged.voiceMigrationState, .fallbackNoticeAcknowledged)
    XCTAssertEqual(acknowledged.originalVoiceID, rawVoiceID)
    XCTAssertEqual(acknowledged.resolvedVoiceID, VoiceProfile.sora.id)
    XCTAssertEqual(acknowledged.schemaMigrationMarker, .v2Resolved)
  }

  @MainActor
  func testDuplicateRepairPrefersLatestDateThenGreatestCanonicalUUID() throws {
    let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let newerID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let profile = makeProfile(id: profileID, selectedVoiceID: "legacy-duplicate-voice")
    let fixture = try makeFixture(profile: profile, availableVoiceIDs: [])
    let context = fixture.container.mainContext
    let timestamp = fixture.now
    let validOlder = PersistedLocalSettings(
      id: profileID,
      profileID: profileID,
      voiceMigrationStateRawValue: VoiceMigrationState.unresolved.rawValue,
      voiceMigrationUpdatedAt: nil,
      schemaMigrationMarkerRawValue: SchemaMigrationMarker.v2Unresolved.rawValue
    )
    let laterInvalid = PersistedLocalSettings(
      id: newerID,
      profileID: profileID,
      voiceMigrationStateRawValue: VoiceMigrationState.unresolved.rawValue,
      voiceMigrationUpdatedAt: timestamp,
      schemaMigrationMarkerRawValue: SchemaMigrationMarker.v2Unresolved.rawValue
    )
    context.insert(validOlder)
    context.insert(laterInvalid)

    let repaired = try XCTUnwrap(try fixture.repository.fetchSettings(profileID: profileID))
    XCTAssertEqual(repaired.voiceMigrationState, .corruptRecoveryPending)
    XCTAssertEqual(repaired.originalVoiceID, "legacy-duplicate-voice")
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<PersistedLocalSettings>()).filter {
        $0.profileID == profileID
      }.count,
      1
    )
  }
  @MainActor
  func testDuplicateRepairUsesGreatestUUIDWhenMigrationDatesTie() throws {
    let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
    let rawVoiceID = "legacy-tie-break-voice"
    let profile = makeProfile(id: profileID, selectedVoiceID: rawVoiceID)
    let fixture = try makeFixture(profile: profile, availableVoiceIDs: [])
    let context = fixture.container.mainContext
    let timestamp = fixture.now
    let validEarlierID = PersistedLocalSettings(
      id: profileID,
      profileID: profileID,
      voiceMigrationStateRawValue: VoiceMigrationState.noFallbackNoticePending.rawValue,
      voiceMigrationOriginalVoiceID: rawVoiceID,
      voiceMigrationResolvedVoiceID: nil,
      voiceMigrationUpdatedAt: timestamp,
      schemaMigrationMarkerRawValue: SchemaMigrationMarker.v2Unresolved.rawValue
    )
    let invalidLaterID = PersistedLocalSettings(
      id: laterID,
      profileID: profileID,
      voiceMigrationStateRawValue: VoiceMigrationState.unresolved.rawValue,
      voiceMigrationUpdatedAt: timestamp,
      schemaMigrationMarkerRawValue: SchemaMigrationMarker.v2Unresolved.rawValue
    )
    context.insert(validEarlierID)
    context.insert(invalidLaterID)

    let repaired = try XCTUnwrap(try fixture.repository.fetchSettings(profileID: profileID))

    XCTAssertEqual(repaired.voiceMigrationState, .corruptRecoveryPending)
    XCTAssertEqual(repaired.originalVoiceID, rawVoiceID)
  }

  @MainActor
  func testSelectionRequiresAnAvailableCatalogueVoice() throws {
    let profile = makeProfile(selectedVoiceID: VoiceProfile.moru.id)
    let fixture = try makeFixture(profile: profile, availableVoiceIDs: [VoiceProfile.yuna.id])

    XCTAssertThrowsError(
      try fixture.repository.selectVoice(profileID: profile.id, voiceID: VoiceProfile.moru.id)
    )
    XCTAssertThrowsError(
      try fixture.repository.selectVoice(profileID: profile.id, voiceID: VoiceProfile.sora.id)
    )

    let selected = try fixture.repository.selectVoice(
      profileID: profile.id,
      voiceID: VoiceProfile.yuna.id
    )
    XCTAssertEqual(selected.voiceMigrationState, .resolved)
    XCTAssertNil(selected.originalVoiceID)
    XCTAssertEqual(selected.resolvedVoiceID, VoiceProfile.yuna.id)
    XCTAssertEqual(try fixture.repository.fetchProfile()?.selectedVoice.id, VoiceProfile.yuna.id)
  }

  @MainActor
  func testUnknownVoiceRawIDRoundTripsWithoutFallbackCollapse() {
    let unknownVoiceID = "third-party-legacy-voice"
    let persisted = PersistedLocalProfile(
      id: UUID(),
      displayName: "Unknown voice user",
      selectedVoiceID: unknownVoiceID,
      createdAt: .distantPast,
      updatedAt: .distantPast
    )

    let profile = SwiftDataMapper.makeDomainProfile(from: persisted)
    let roundTripped = SwiftDataMapper.makePersistedProfile(from: profile)

    XCTAssertEqual(profile.selectedVoice.id, unknownVoiceID)
    XCTAssertEqual(roundTripped.selectedVoiceID, unknownVoiceID)
    XCTAssertEqual(VoiceSelection(rawID: unknownVoiceID), .unavailable(rawID: unknownVoiceID))
    XCTAssertEqual(
      VoiceSelection(rawID: VoiceProfile.moru.id),
      .unavailable(rawID: VoiceProfile.moru.id)
    )
    XCTAssertEqual(VoiceSelection(rawID: VoiceProfile.yuna.id), .available(.yuna))
  }

  @MainActor
  private func makeFixture(
    profile: LocalProfile,
    availableVoiceIDs: Set<String>
  ) throws -> LocalSettingsFixture {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let now = Date(timeIntervalSince1970: 1_752_854_400)
    let repository = SwiftDataLocalProfileRepository(
      modelContext: container.mainContext,
      availabilityProbe: TestVoiceAvailabilityProbe(availableVoiceIDs: availableVoiceIDs),
      now: { now }
    )
    try repository.saveProfile(profile)
    return LocalSettingsFixture(container: container, repository: repository, now: now)
  }

  private func makeProfile(
    id: UUID = UUID(),
    selectedVoiceID: String
  ) -> LocalProfile {
    LocalProfile(
      id: id,
      selectedVoice: VoiceProfile.preserving(id: selectedVoiceID),
      createdAt: .distantPast,
      updatedAt: .distantPast
    )
  }
}

private struct LocalSettingsFixture {
  let container: ModelContainer
  let repository: SwiftDataLocalProfileRepository
  let now: Date
}

private struct TestVoiceAvailabilityProbe: VoiceAvailabilityProbing {
  let availableVoiceIDs: Set<String>

  func isAvailable(_ voice: VoiceProfile) -> Bool {
    availableVoiceIDs.contains(voice.id)
  }
}
