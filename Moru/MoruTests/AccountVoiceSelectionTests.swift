//
//  AccountVoiceSelectionTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest

import Moya

@testable import Moru

@MainActor
final class AccountVoiceSelectionTests: XCTestCase {
  func testVoiceTargetsMatchSwaggerAndUseBearerWithoutLoggingPayload() throws {
    XCTAssertEqual(VoiceTarget.catalogue.path, "/tts")
    XCTAssertEqual(VoiceTarget.catalogue.method, .get)
    XCTAssertEqual(VoiceTarget.catalogue.authenticationRequirement, .bearer)

    let update = VoiceTarget.updateSelection(TtsUpdateRequestDTO(ttsId: 42))
    XCTAssertEqual(update.path, "/members/me/tts")
    XCTAssertEqual(update.method, .patch)
    XCTAssertEqual(update.authenticationRequirement, .bearer)

    let adapter = MoyaTargetAdapter(
      target: update,
      baseURL: NetworkConfiguration.production.baseURL,
      requestAccessToken: "voice-secret-token"
    )
    let message = NetworkLogPlugin.requestMessage(for: adapter)
    XCTAssertEqual(message, "➡️ PATCH /members/me/tts")
    XCTAssertFalse(message.contains("42"))
    XCTAssertFalse(message.contains("voice-secret-token"))
  }

  func testRemoteCatalogueAndPatchDecodeValidatedSwaggerContract() async throws {
    let catalogueCapture = VoiceRequestCapturePlugin()
    let catalogueSource = DefaultVoiceRemoteDataSource(
      apiClient: makeClient(
        data: catalogueData(),
        additionalPlugins: [catalogueCapture]
      )
    )

    let voices = try await catalogueSource.fetchVoices(memberID: 96)

    XCTAssertEqual(
      voices,
      [
        ServerVoiceCatalogueItem(
          ttsID: 1,
          voiceCode: "MINSEO",
          displayName: "민서",
          description: "따뜻한 친구",
          proOnly: false
        )
      ]
    )
    let catalogueRequest = try XCTUnwrap(catalogueCapture.request)
    XCTAssertEqual(catalogueRequest.httpMethod, "GET")
    XCTAssertEqual(catalogueRequest.url?.path, "/tts")
    XCTAssertEqual(
      catalogueRequest.value(forHTTPHeaderField: "Authorization"),
      "Bearer access-token"
    )
    XCTAssertNil(catalogueRequest.httpBody)

    let updateCapture = VoiceRequestCapturePlugin()
    let updateSource = DefaultVoiceRemoteDataSource(
      apiClient: makeClient(
        data: updateData(),
        additionalPlugins: [updateCapture]
      )
    )
    let update = try await updateSource.updateSelection(
      ttsID: 1,
      memberID: 96
    )

    XCTAssertEqual(update.memberID, 96)
    XCTAssertEqual(update.ttsID, 1)
    XCTAssertEqual(update.voiceCode, "MINSEO")
    let updateRequest = try XCTUnwrap(updateCapture.request)
    XCTAssertEqual(updateRequest.httpMethod, "PATCH")
    XCTAssertEqual(updateRequest.url?.path, "/members/me/tts")
    XCTAssertEqual(
      try jsonBody(updateRequest)["ttsId"] as? Int,
      1
    )
  }

  func testAccountBoundGetAndPatchRejectWrongMemberBeforeNetworkRequest()
    async {
    let catalogueCapture = VoiceRequestCapturePlugin()
    let catalogueSource = DefaultVoiceRemoteDataSource(
      apiClient: makeClient(
        data: catalogueData(),
        additionalPlugins: [catalogueCapture]
      )
    )

    await assertAccountAuthorizationChanged {
      _ = try await catalogueSource.fetchVoices(memberID: 97)
    }
    XCTAssertNil(
      catalogueCapture.request,
      "A catalogue request for another member must fail before transport."
    )

    let updateCapture = VoiceRequestCapturePlugin()
    let updateSource = DefaultVoiceRemoteDataSource(
      apiClient: makeClient(
        data: updateData(),
        additionalPlugins: [updateCapture]
      )
    )

    await assertAccountAuthorizationChanged {
      _ = try await updateSource.updateSelection(
        ttsID: 1,
        memberID: 97
      )
    }
    XCTAssertNil(
      updateCapture.request,
      "A selection update for another member must fail before transport."
    )
  }

  func testMalformedAndInvalidCatalogueAreRejectedWithoutPartialAcceptance() async {
    let malformed = Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": {
          "voices": [{
            "ttsId": 1,
            "voiceCode": "MINSEO",
            "displayName": "민서"
          }]
        }
      }
      """.utf8
    )
    let malformedSource = DefaultVoiceRemoteDataSource(
      apiClient: makeClient(data: malformed)
    )

    await assertError(APIError.self) {
      _ = try await malformedSource.fetchVoices(memberID: 96)
    }

    let duplicate = Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": {
          "voices": [
            {
              "ttsId": 1,
              "voiceCode": "FUTURE",
              "displayName": "첫 번째",
              "description": null,
              "proOnly": false
            },
            {
              "ttsId": 1,
              "voiceCode": "OTHER",
              "displayName": "두 번째",
              "description": null,
              "proOnly": false
            }
          ]
        }
      }
      """.utf8
    )
    let duplicateSource = DefaultVoiceRemoteDataSource(
      apiClient: makeClient(data: duplicate)
    )

    await assertError(AccountVoiceRemoteError.self) {
      _ = try await duplicateSource.fetchVoices(memberID: 96)
    }
  }

  func testOfflineTimeoutAndServerFailureUseBundledFallbackWhenCacheIsEmpty() async throws {
    let failures: [Error] = [
      APIError.transport(code: URLError.notConnectedToInternet.rawValue, message: "offline"),
      APIError.transport(code: URLError.timedOut.rawValue, message: "timeout"),
      APIError.server(statusCode: 503, code: "COMMON500", message: "unavailable"),
    ]

    for failure in failures {
      let fixture = try makeFixture(
        remoteDataSource: VoiceRemoteStub(fetchResult: .failure(failure)),
        signedIn: true
      )

      let snapshot = await fixture.useCase.loadCatalogue()

      XCTAssertEqual(snapshot.options.count, VoiceProfile.localVoices.count)
      XCTAssertTrue(snapshot.options.allSatisfy { $0.source == .bundledFallback })
      XCTAssertNotNil(snapshot.notice)
      XCTAssertTrue(
        try fixture.repository.catalog(memberID: Self.memberID).isEmpty
      )
    }
  }

  func testCacheIsAccountScopedAndUsedAfterServerFailure() async throws {
    let fixture = try makeFixture(
      remoteDataSource: VoiceRemoteStub(
        fetchResult: .failure(APIError.transport(code: -1009, message: "offline"))
      ),
      signedIn: true
    )
    try fixture.repository.replaceCatalog(
      [
        try catalogEntry(
          memberID: Self.memberID,
          ttsID: 3,
          voiceCode: "CACHED",
          displayName: "캐시"
        )
      ],
      memberID: Self.memberID
    )
    try fixture.repository.replaceCatalog(
      [
        try catalogEntry(
          memberID: 97,
          ttsID: 7,
          voiceCode: "OTHER_ACCOUNT",
          displayName: "다른 계정"
        )
      ],
      memberID: 97
    )

    let snapshot = await fixture.useCase.loadCatalogue()

    XCTAssertEqual(
      snapshot.options
        .filter { $0.source == .serverCatalogue }
        .compactMap(\.serverVoiceCode),
      ["CACHED"]
    )
    XCTAssertEqual(
      snapshot.options
        .filter { $0.source == .bundledFallback }
        .compactMap(\.localVoice?.id),
      VoiceProfile.localVoices.map(\.id)
    )
    XCTAssertFalse(snapshot.options.contains { $0.serverVoiceCode == "OTHER_ACCOUNT" })
    XCTAssertNotNil(snapshot.notice)
  }

  func testSuccessfulGetReplacesStaleAccountCatalogue() async throws {
    let fixture = try makeFixture(
      remoteDataSource: VoiceRemoteStub(
        fetchResult: .success(
          [
            serverVoice(
              ttsID: 8,
              code: "FRESH",
              name: "최신 서버 음성"
            )
          ]
        )
      ),
      signedIn: true
    )
    try fixture.repository.replaceCatalog(
      [
        try catalogEntry(
          memberID: Self.memberID,
          ttsID: 3,
          voiceCode: "STALE",
          displayName: "오래된 캐시"
        )
      ],
      memberID: Self.memberID
    )

    let snapshot = await fixture.useCase.loadCatalogue()
    let persisted = try fixture.repository.catalog(memberID: Self.memberID)

    XCTAssertNil(snapshot.notice)
    XCTAssertEqual(persisted.map(\.voiceCode), ["FRESH"])
    XCTAssertEqual(persisted.map(\.displayName), ["최신 서버 음성"])
    XCTAssertEqual(
      snapshot.options
        .filter { $0.source == .serverCatalogue }
        .compactMap(\.serverVoiceCode),
      ["FRESH"]
    )
    XCTAssertFalse(snapshot.options.contains { $0.serverVoiceCode == "STALE" })
  }

  func testProductionCompatibilityTableDoesNotInferAndKeepsBundledVoices()
    async throws {
    let fixture = try makeFixture(
      remoteDataSource: VoiceRemoteStub(
        fetchResult: .success(
          [
            ServerVoiceCatalogueItem(
              ttsID: 1,
              voiceCode: "MINSEO",
              displayName: VoiceProfile.aoede.displayName,
              description: "Swagger example",
              proOnly: false
            ),
            ServerVoiceCatalogueItem(
              ttsID: 2,
              voiceCode: "FUTURE_PRO",
              displayName: "새 음성",
              description: nil,
              proOnly: true
            ),
          ]
        )
      ),
      signedIn: true,
      compatibilityTable: .production
    )

    let snapshot = await fixture.useCase.loadCatalogue()
    let bundledOptions = snapshot.options.filter {
      $0.source == .bundledFallback
    }

    XCTAssertEqual(
      bundledOptions.compactMap(\.localVoice?.id),
      VoiceProfile.localVoices.map(\.id)
    )
    XCTAssertEqual(
      snapshot.options.count,
      VoiceProfile.localVoices.count + 2
    )
    XCTAssertEqual(
      snapshot.options.first { $0.serverVoiceCode == "MINSEO" }?.availability,
      .incompatible
    )
    XCTAssertNil(
      snapshot.options.first { $0.serverVoiceCode == "MINSEO" }?.localVoice,
      "A matching display name must never create compatibility."
    )
    XCTAssertEqual(
      snapshot.options.first { $0.serverVoiceCode == "FUTURE_PRO" }?.availability,
      .proOnly
    )
  }

  func testUnavailableAuthoritativeMismatchCanKeepBundledDeviceVoice()
    async throws {
    let scenarios: [
      (
        voiceCode: String,
        proOnly: Bool,
        compatibility: VoiceCompatibilityTable,
        expectedAvailability: AccountVoiceAvailability
      )
    ] = [
      (
        voiceCode: "PRO_CHARON",
        proOnly: true,
        compatibility: VoiceCompatibilityTable(
          entries: ["PRO_CHARON": VoiceProfile.charon.id]
        ),
        expectedAvailability: .proOnly
      ),
      (
        voiceCode: "NOT_MAPPED",
        proOnly: false,
        compatibility: VoiceCompatibilityTable(entries: [:]),
        expectedAvailability: .incompatible
      ),
    ]

    for scenario in scenarios {
      let fixture = try makeFixture(
        remoteDataSource: VoiceRemoteStub(
          fetchResult: .failure(
            APIError.transport(code: -1009, message: "offline")
          )
        ),
        signedIn: true,
        compatibilityTable: scenario.compatibility,
        selectedVoice: .aoede
      )
      try fixture.repository.replaceCatalog(
        [
          try catalogEntry(
            memberID: Self.memberID,
            ttsID: 21,
            voiceCode: scenario.voiceCode,
            displayName: "서버 선택 음성",
            proOnly: scenario.proOnly,
            isAuthoritativeSelection: true
          )
        ],
        memberID: Self.memberID
      )

      let snapshot = await fixture.useCase.loadCatalogue()
      let mismatch = try XCTUnwrap(snapshot.mismatch)

      XCTAssertEqual(mismatch.localVoice, .aoede)
      XCTAssertEqual(
        mismatch.serverVoice.serverVoiceCode,
        scenario.voiceCode
      )
      XCTAssertEqual(
        mismatch.serverVoice.availability,
        scenario.expectedAvailability
      )
      XCTAssertTrue(mismatch.serverVoice.isAuthoritativeServerSelection)

      let result = try await fixture.useCase.resolveMismatch(
        mismatch,
        choice: .keepDevice
      )

      XCTAssertEqual(result.profileResult.profile.selectedVoice, .aoede)
      XCTAssertEqual(result.serverDisposition, .notApplicable)
      XCTAssertEqual(
        try fixture.localProfileRepository.fetchProfile()?.selectedVoice,
        .aoede
      )
      XCTAssertTrue(
        try fixture.repository.mutations(
          memberID: Self.memberID,
          dueAt: .distantFuture,
          includeBlocked: true
        ).isEmpty
      )
      XCTAssertTrue(fixture.serverSynchronizer.calls.isEmpty)
      XCTAssertTrue(
        try fixture.repository
          .catalog(memberID: Self.memberID)
          .allSatisfy {
            VoiceCatalogMetadata.decode(rawValue: $0.tierRawValue)?
              .isAuthoritativeSelection == false
          }
      )

      let reloaded = await fixture.useCase.loadCatalogue()
      XCTAssertNil(reloaded.mismatch)
    }
  }

  func testUnknownProIncompatibleAndMissingBundleOptionsAreDisabled() async throws {
    let compatibility = VoiceCompatibilityTable(
      entries: ["KNOWN_NO_AUDIO": VoiceProfile.aoede.id]
    )
    let fixture = try makeFixture(
      remoteDataSource: VoiceRemoteStub(
        fetchResult: .failure(
          APIError.transport(code: -1009, message: "offline")
        )
      ),
      signedIn: true,
      compatibilityTable: compatibility
    )
    try fixture.repository.replaceCatalog(
      [
        ServerVoiceCatalogEntry(
          memberID: Self.memberID,
          voiceCode: "UNKNOWN_METADATA",
          displayName: "미래 메타데이터",
          tierRawValue: "future-tier",
          isLocallyPlayable: true,
          fetchedAt: Date()
        ),
        try catalogEntry(
          memberID: Self.memberID,
          ttsID: 2,
          voiceCode: "PRO",
          displayName: "PRO",
          proOnly: true
        ),
        try catalogEntry(
          memberID: Self.memberID,
          ttsID: 3,
          voiceCode: "NOT_MAPPED",
          displayName: "호환 없음"
        ),
        try catalogEntry(
          memberID: Self.memberID,
          ttsID: 4,
          voiceCode: "KNOWN_NO_AUDIO",
          displayName: "번들 없음",
          isLocallyPlayable: false
        ),
      ],
      memberID: Self.memberID
    )

    let snapshot = await fixture.useCase.loadCatalogue()
    let serverOptions = snapshot.options.filter {
      $0.source == .serverCatalogue
    }
    let availability = Dictionary(
      uniqueKeysWithValues: serverOptions.compactMap { option in
        option.serverVoiceCode.map { ($0, option.availability) }
      }
    )

    XCTAssertEqual(availability["UNKNOWN_METADATA"], .unknownMetadata)
    XCTAssertEqual(availability["PRO"], .proOnly)
    XCTAssertEqual(availability["NOT_MAPPED"], .incompatible)
    XCTAssertEqual(availability["KNOWN_NO_AUDIO"], .missingBundledAudio)
    XCTAssertTrue(serverOptions.allSatisfy { !$0.availability.isSelectable })
    XCTAssertEqual(
      snapshot.options.filter { $0.source == .bundledFallback }.count,
      VoiceProfile.localVoices.count
    )
    XCTAssertNotNil(snapshot.notice)
  }

  func testLocalSelectionIsSavedBeforeVersionedOutboxAndLatestValueCoalesces() async throws {
    let compatibility = VoiceCompatibilityTable(
      entries: [
        "TEST_AOEDE": VoiceProfile.aoede.id,
        "TEST_CHARON": VoiceProfile.charon.id,
      ]
    )
    let fixture = try makeFixture(
      remoteDataSource: VoiceRemoteStub(
        fetchResult: .success(
          [
            serverVoice(ttsID: 11, code: "TEST_AOEDE", name: "테스트 A"),
            serverVoice(ttsID: 12, code: "TEST_CHARON", name: "테스트 B"),
          ]
        )
      ),
      signedIn: true,
      compatibilityTable: compatibility
    )
    let snapshot = await fixture.useCase.loadCatalogue()
    let aoede = try XCTUnwrap(
      snapshot.options.first { $0.localVoice?.id == VoiceProfile.aoede.id }
    )
    let charon = try XCTUnwrap(
      snapshot.options.first { $0.localVoice?.id == VoiceProfile.charon.id }
    )

    let first = try await fixture.useCase.select(aoede)
    XCTAssertEqual(first.profileResult.profile.selectedVoice, .aoede)
    XCTAssertEqual(
      try fixture.localProfileRepository.fetchProfile()?.selectedVoice,
      .aoede
    )
    let firstMutation = try XCTUnwrap(
      try fixture.repository.mutations(
        memberID: Self.memberID,
        dueAt: .distantFuture,
        includeBlocked: true
      ).first
    )
    let firstPayload = try VoiceSelectionMutationPayload.decode(
      firstMutation.payload
    )
    XCTAssertEqual(firstPayload.version, VoiceSelectionMutationPayload.currentVersion)
    XCTAssertEqual(firstPayload.ttsID, 11)
    XCTAssertEqual(firstPayload.localVoiceID, VoiceProfile.aoede.id)
    XCTAssertEqual(fixture.serverSynchronizer.calls.count, 1)
    XCTAssertEqual(
      fixture.serverSynchronizer.calls.first?.memberID,
      Self.memberID
    )
    XCTAssertEqual(
      fixture.serverSynchronizer.calls.first?.trigger,
      .manual
    )

    _ = try await fixture.useCase.select(charon)
    let mutations = try fixture.repository.mutations(
      memberID: Self.memberID,
      dueAt: .distantFuture,
      includeBlocked: true
    )
    let latest = try XCTUnwrap(mutations.first)
    let latestPayload = try VoiceSelectionMutationPayload.decode(latest.payload)
    XCTAssertEqual(mutations.count, 1)
    XCTAssertEqual(latest.id, firstMutation.id)
    XCTAssertNotEqual(latest.idempotencyKey, firstMutation.idempotencyKey)
    XCTAssertEqual(latestPayload.ttsID, 12)
    XCTAssertEqual(latestPayload.localVoiceID, VoiceProfile.charon.id)
    XCTAssertEqual(fixture.serverSynchronizer.calls.count, 2)
  }

  func testExecutorAcceptsEquivalentCanonicalVoiceAndRejectsDifferentVoice()
    async throws {
    let compatibility = VoiceCompatibilityTable(
      entries: [
        "TEST_AOEDE": VoiceProfile.aoede.id,
        "TEST_CHARON": VoiceProfile.charon.id,
      ]
    )
    let fixture = try makeFixture(
      remoteDataSource: VoiceRemoteStub(fetchResult: .success([])),
      signedIn: true,
      compatibilityTable: compatibility
    )
    try fixture.repository.replaceCatalog(
      [
        try catalogEntry(
          memberID: Self.memberID,
          ttsID: 11,
          voiceCode: "TEST_AOEDE",
          displayName: "테스트"
        ),
        try catalogEntry(
          memberID: Self.memberID,
          ttsID: 12,
          voiceCode: "TEST_CHARON",
          displayName: "이전 서버 선택",
          isAuthoritativeSelection: true
        )
      ],
      memberID: Self.memberID
    )
    let mutation = try fixture.repository.enqueue(
      EnqueuedServerMutation(
        memberID: Self.memberID,
        operation: .replaceVoiceSelection,
        operationKey: VoiceSelectionMutationPayload.operationKey,
        payload: try VoiceSelectionMutationPayload(
          memberID: Self.memberID,
          ttsID: 11,
          voiceCode: "TEST_AOEDE",
          localVoiceID: VoiceProfile.aoede.id
        ).encoded()
      )
    )
    let successRemote = VoiceRemoteStub(
      fetchResult: .success([]),
      updateResult: .success(
        AuthoritativeServerVoiceSelection(
          memberID: Self.memberID,
          ttsID: 11,
          voiceCode: "TEST_AOEDE",
          displayName: "서버 표시 이름"
        )
      )
    )
    let successExecutor = VoiceSelectionMutationExecutor(
      remoteService: successRemote,
      catalogueRepository: fixture.repository,
      compatibilityTable: compatibility
    )

    let executionResult = try await successExecutor.execute(mutation)
    XCTAssertEqual(executionResult, .sent)
    let metadataByVoiceCode = try Dictionary(
      uniqueKeysWithValues: fixture.repository
        .catalog(memberID: Self.memberID)
        .map { entry in
          (
            entry.voiceCode,
            try XCTUnwrap(
              VoiceCatalogMetadata.decode(rawValue: entry.tierRawValue)
            )
          )
        }
    )
    XCTAssertTrue(
      try XCTUnwrap(
        metadataByVoiceCode["TEST_AOEDE"]
      ).isAuthoritativeSelection
    )
    XCTAssertFalse(
      try XCTUnwrap(
        metadataByVoiceCode["TEST_CHARON"]
      ).isAuthoritativeSelection,
      "The latest authoritative response must replace the previous selection."
    )

    let canonicalExecutor = VoiceSelectionMutationExecutor(
      remoteService: VoiceRemoteStub(
        fetchResult: .success([]),
        updateResult: .success(
          AuthoritativeServerVoiceSelection(
            memberID: Self.memberID,
            ttsID: 111,
            voiceCode: "TEST_AOEDE",
            displayName: "서버 canonical ID"
          )
        )
      ),
      catalogueRepository: fixture.repository,
      compatibilityTable: compatibility
    )

    let canonicalResult = try await canonicalExecutor.execute(mutation)
    XCTAssertEqual(
      canonicalResult,
      .sent,
      "A canonical ID change for the same local voice satisfies user intent."
    )
    let canonicalEntry = try XCTUnwrap(
      fixture.repository
        .catalog(memberID: Self.memberID)
        .first { $0.voiceCode == "TEST_AOEDE" }
    )
    XCTAssertEqual(
      VoiceCatalogMetadata.decode(
        rawValue: canonicalEntry.tierRawValue
      )?.ttsID,
      111
    )

    let divergentRemote = VoiceRemoteStub(
      fetchResult: .success([]),
      updateResult: .success(
        AuthoritativeServerVoiceSelection(
          memberID: Self.memberID,
          ttsID: 12,
          voiceCode: "TEST_CHARON",
          displayName: "서버가 확정한 다른 음성"
        )
      )
    )
    let divergentExecutor = VoiceSelectionMutationExecutor(
      remoteService: divergentRemote,
      catalogueRepository: fixture.repository,
      compatibilityTable: compatibility
    )

    do {
      _ = try await divergentExecutor.execute(mutation)
      XCTFail("Expected the divergent authoritative response to be rejected.")
    } catch let error as AccountVoiceRemoteError {
      XCTAssertEqual(error, .authoritativeMismatch)
    } catch {
      XCTFail("Expected authoritativeMismatch, got \(error)")
    }
    XCTAssertEqual(
      try fixture.repository
        .catalog(memberID: Self.memberID)
        .filter {
          VoiceCatalogMetadata.decode(rawValue: $0.tierRawValue)?
            .isAuthoritativeSelection == true
        }
        .map(\.voiceCode),
      ["TEST_CHARON"],
      "The latest same-account server state must be cached before mismatch."
    )

    let mismatchRemote = VoiceRemoteStub(
      fetchResult: .success([]),
      updateResult: .success(
        AuthoritativeServerVoiceSelection(
          memberID: 999,
          ttsID: 11,
          voiceCode: "TEST_AOEDE",
          displayName: "다른 계정"
        )
      )
    )
    let mismatchExecutor = VoiceSelectionMutationExecutor(
      remoteService: mismatchRemote,
      catalogueRepository: fixture.repository,
      compatibilityTable: compatibility
    )

    await assertError(AccountVoiceRemoteError.self) {
      _ = try await mismatchExecutor.execute(mutation)
    }
  }

  func testPatchConflictMissingFromSuccessfulGetRemainsVisibleForResolution()
    async throws {
    let compatibility = VoiceCompatibilityTable(
      entries: ["TEST_AOEDE": VoiceProfile.aoede.id]
    )
    let fixture = try makeFixture(
      remoteDataSource: VoiceRemoteStub(
        fetchResult: .success(
          [
            serverVoice(
              ttsID: 11,
              code: "TEST_AOEDE",
              name: "요청한 음성"
            )
          ]
        )
      ),
      signedIn: true,
      compatibilityTable: compatibility,
      selectedVoice: .aoede
    )
    let mutation = try fixture.repository.enqueue(
      EnqueuedServerMutation(
        memberID: Self.memberID,
        operation: .replaceVoiceSelection,
        operationKey: VoiceSelectionMutationPayload.operationKey,
        payload: try VoiceSelectionMutationPayload(
          memberID: Self.memberID,
          ttsID: 11,
          voiceCode: "TEST_AOEDE",
          localVoiceID: VoiceProfile.aoede.id
        ).encoded()
      )
    )
    let executor = VoiceSelectionMutationExecutor(
      remoteService: VoiceRemoteStub(
        fetchResult: .success([]),
        updateResult: .success(
          AuthoritativeServerVoiceSelection(
            memberID: Self.memberID,
            ttsID: 99,
            voiceCode: "SERVER_UNKNOWN",
            displayName: "목록에 없는 서버 선택"
          )
        )
      ),
      catalogueRepository: fixture.repository,
      compatibilityTable: compatibility
    )

    do {
      _ = try await executor.execute(mutation)
      XCTFail("Expected the divergent PATCH response to remain unresolved.")
    } catch let error as AccountVoiceRemoteError {
      XCTAssertEqual(error, .authoritativeMismatch)
    } catch {
      XCTFail("Expected authoritativeMismatch, got \(error)")
    }

    let snapshot = await fixture.useCase.loadCatalogue()
    let mismatch = try XCTUnwrap(snapshot.mismatch)

    XCTAssertEqual(mismatch.serverVoice.serverVoiceCode, "SERVER_UNKNOWN")
    XCTAssertEqual(mismatch.serverVoice.availability, .notInCatalogue)
    XCTAssertTrue(mismatch.serverVoice.isAuthoritativeServerSelection)
    XCTAssertEqual(
      try fixture.repository
        .catalog(memberID: Self.memberID)
        .map(\.voiceCode)
        .sorted(),
      ["SERVER_UNKNOWN", "TEST_AOEDE"]
    )
  }

  func testSuccessfulGetReconcilesRotatedTtsIDForSameAuthoritativeVoiceCode()
    async throws {
    let compatibility = VoiceCompatibilityTable(
      entries: ["TEST_AOEDE": VoiceProfile.aoede.id]
    )
    let fixture = try makeFixture(
      remoteDataSource: VoiceRemoteStub(
        fetchResult: .success(
          [
            serverVoice(
              ttsID: 100,
              code: "TEST_AOEDE",
              name: "재발급된 음성"
            )
          ]
        )
      ),
      signedIn: true,
      compatibilityTable: compatibility,
      selectedVoice: .charon
    )
    try fixture.repository.recordAuthoritativeSelection(
      AuthoritativeServerVoiceSelection(
        memberID: Self.memberID,
        ttsID: 99,
        voiceCode: "TEST_AOEDE",
        displayName: "이전 ID의 같은 음성"
      )
    )

    let snapshot = await fixture.useCase.loadCatalogue()
    let mismatch = try XCTUnwrap(snapshot.mismatch)
    let persisted = try XCTUnwrap(
      fixture.repository.catalog(memberID: Self.memberID).first
    )
    let metadata = try XCTUnwrap(
      VoiceCatalogMetadata.decode(rawValue: persisted.tierRawValue)
    )

    XCTAssertNil(snapshot.notice)
    XCTAssertEqual(
      snapshot.options.filter { $0.source == .serverCatalogue }.count,
      1
    )
    XCTAssertEqual(mismatch.localVoice, .charon)
    XCTAssertEqual(mismatch.serverVoice.localVoice, .aoede)
    XCTAssertEqual(mismatch.serverVoice.serverTtsID, 100)
    XCTAssertEqual(metadata.ttsID, 100)
    XCTAssertTrue(metadata.isAuthoritativeSelection)
    XCTAssertTrue(metadata.isListedInCatalogue)
  }

  func testMismatchRequiresExplicitChoiceAndNeverOverwritesLocalOnLoad() async throws {
    let compatibility = VoiceCompatibilityTable(
      entries: [
        "TEST_AOEDE": VoiceProfile.aoede.id,
        "TEST_CHARON": VoiceProfile.charon.id,
      ]
    )
    let fixture = try makeFixture(
      remoteDataSource: VoiceRemoteStub(
        fetchResult: .failure(
          APIError.transport(code: -1009, message: "offline")
        )
      ),
      signedIn: true,
      compatibilityTable: compatibility,
      selectedVoice: .aoede
    )
    try fixture.repository.replaceCatalog(
      [
        try catalogEntry(
          memberID: Self.memberID,
          ttsID: 11,
          voiceCode: "TEST_AOEDE",
          displayName: "기기 음성"
        ),
        try catalogEntry(
          memberID: Self.memberID,
          ttsID: 12,
          voiceCode: "TEST_CHARON",
          displayName: "서버 음성",
          isAuthoritativeSelection: true
        ),
      ],
      memberID: Self.memberID
    )

    let snapshot = await fixture.useCase.loadCatalogue()

    XCTAssertEqual(
      try fixture.localProfileRepository.fetchProfile()?.selectedVoice,
      .aoede,
      "Catalogue load must never overwrite the local selection."
    )
    let mismatch = try XCTUnwrap(snapshot.mismatch)
    XCTAssertEqual(mismatch.localVoice, .aoede)
    XCTAssertEqual(mismatch.serverVoice.localVoice, .charon)

    let result = try await fixture.useCase.resolveMismatch(
      mismatch,
      choice: .useServer
    )
    XCTAssertEqual(result.profileResult.profile.selectedVoice, .charon)
  }

  func testSignedOutSelectionKeepsLocalVoiceAndCreatesNoAccountOutbox() async throws {
    let fixture = try makeFixture(
      remoteDataSource: VoiceRemoteStub(fetchResult: .success([])),
      signedIn: false,
      selectedVoice: .charon
    )

    let snapshot = await fixture.useCase.loadCatalogue()
    let kore = try XCTUnwrap(
      snapshot.options.first { $0.localVoice?.id == VoiceProfile.kore.id }
    )
    let result = try await fixture.useCase.select(kore)

    XCTAssertEqual(result.profileResult.profile.selectedVoice, .kore)
    XCTAssertEqual(result.serverDisposition, .notApplicable)
    XCTAssertEqual(
      try fixture.localProfileRepository.fetchProfile()?.selectedVoice,
      .kore
    )
    XCTAssertTrue(
      try fixture.repository.mutations(
        memberID: Self.memberID,
        dueAt: .distantFuture,
        includeBlocked: true
      ).isEmpty
    )
  }

  func testServerOptionFromPreviousAccountCannotMutateCurrentAccount() async throws {
    let compatibility = VoiceCompatibilityTable(
      entries: ["TEST_AOEDE": VoiceProfile.aoede.id]
    )
    let fixture = try makeFixture(
      remoteDataSource: VoiceRemoteStub(
        fetchResult: .success(
          [serverVoice(ttsID: 11, code: "TEST_AOEDE", name: "테스트")]
        )
      ),
      signedIn: true,
      compatibilityTable: compatibility,
      selectedVoice: .charon
    )
    let snapshot = await fixture.useCase.loadCatalogue()
    let staleOption = try XCTUnwrap(snapshot.options.first)
    fixture.memberProvider.signedInMemberID = 97

    await assertError(ProfileSettingsUseCaseError.self) {
      _ = try await fixture.useCase.select(staleOption)
    }

    XCTAssertEqual(
      try fixture.localProfileRepository.fetchProfile()?.selectedVoice,
      .charon
    )
    XCTAssertTrue(
      try fixture.repository.mutations(
        memberID: 97,
        dueAt: .distantFuture,
        includeBlocked: true
      ).isEmpty
    )
  }

  private static let memberID: Int64 = 96

  private func makeFixture(
    remoteDataSource remoteService: any AccountVoiceRemoteServing,
    signedIn: Bool,
    compatibilityTable: VoiceCompatibilityTable = .production,
    selectedVoice: VoiceProfile = .aoede
  ) throws -> VoiceFixture {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataServerPreferenceRepository(
      modelContext: container.mainContext
    )
    let localProfileRepository = SwiftDataLocalProfileRepository(
      modelContext: container.mainContext
    )
    var profile = LocalProfile()
    profile.selectedVoice = selectedVoice
    try localProfileRepository.saveProfile(profile)
    let probe = VoiceAlwaysAvailableProbe()
    let profileUseCase = ProfileSettingsUseCase(
      localProfileRepository: localProfileRepository,
      voiceAvailabilityProbe: probe
    )
    let memberProvider = SignedInMemberStub(
      signedInMemberID: signedIn ? Self.memberID : nil
    )
    let serverSynchronizer = ServerSynchronizerSpy()
    let useCase = AccountVoiceSelectionUseCase(
      profileSettingsUseCase: profileUseCase,
      voiceAvailabilityProbe: probe,
      remoteService: remoteService,
      catalogueRepository: repository,
      mutationRepository: repository,
      serverSynchronizer: serverSynchronizer,
      signedInMemberProvider: memberProvider,
      compatibilityTable: compatibilityTable
    )
    return VoiceFixture(
      container: container,
      repository: repository,
      localProfileRepository: localProfileRepository,
      memberProvider: memberProvider,
      serverSynchronizer: serverSynchronizer,
      useCase: useCase
    )
  }

  private func catalogEntry(
    memberID: Int64,
    ttsID: Int64,
    voiceCode: String,
    displayName: String,
    proOnly: Bool = false,
    isAuthoritativeSelection: Bool = false,
    isLocallyPlayable: Bool = true
  ) throws -> ServerVoiceCatalogEntry {
    ServerVoiceCatalogEntry(
      memberID: memberID,
      voiceCode: voiceCode,
      displayName: displayName,
      tierRawValue: try VoiceCatalogMetadata(
        ttsID: ttsID,
        proOnly: proOnly,
        description: nil,
        isAuthoritativeSelection: isAuthoritativeSelection
      ).encodedRawValue(),
      isLocallyPlayable: isLocallyPlayable,
      fetchedAt: Date()
    )
  }

  private func serverVoice(
    ttsID: Int64,
    code: String,
    name: String
  ) -> ServerVoiceCatalogueItem {
    ServerVoiceCatalogueItem(
      ttsID: ttsID,
      voiceCode: code,
      displayName: name,
      description: nil,
      proOnly: false
    )
  }

  private func assertError<E: Error>(
    _ expectedType: E.Type,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expectedType)")
    } catch is E {
      return
    } catch {
      XCTFail("Expected \(expectedType), got \(error)")
    }
  }

  private func assertAccountAuthorizationChanged(
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected account authorization to reject the request.")
    } catch let error as AccountVoiceRemoteError {
      XCTAssertEqual(error, .accountAuthorizationChanged)
    } catch {
      XCTFail(
        "Expected AccountVoiceRemoteError.accountAuthorizationChanged, "
          + "got \(error)"
      )
    }
  }

  private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try XCTUnwrap(request.httpBody)
    return try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
  }

  nonisolated private func makeClient(
    data: Data,
    additionalPlugins: [any PluginType & Sendable] = []
  ) -> DefaultAPIClient {
    DefaultAPIClient(
      tokenProvider: VoiceAccessTokenProvider(),
      providerFactory: MoyaProviderFactory(
        endpointBuilder: { target in
          let endpoint = MoyaProvider<MultiTarget>.defaultEndpointMapping(
            for: target
          )
          return Endpoint(
            url: endpoint.url,
            sampleResponseClosure: { .networkResponse(200, data) },
            method: endpoint.method,
            task: endpoint.task,
            httpHeaderFields: endpoint.httpHeaderFields
          )
        },
        stubBuilder: { _ in .immediate },
        additionalPlugins: additionalPlugins
      )
    )
  }

  nonisolated private func catalogueData() -> Data {
    Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": {
          "voices": [{
            "ttsId": 1,
            "voiceCode": "MINSEO",
            "displayName": "민서",
            "description": "따뜻한 친구",
            "proOnly": false
          }]
        }
      }
      """.utf8
    )
  }

  nonisolated private func updateData() -> Data {
    Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": {
          "memberId": 96,
          "ttsId": 1,
          "voiceCode": "MINSEO",
          "displayName": "민서"
        }
      }
      """.utf8
    )
  }
}

@MainActor
private struct VoiceFixture {
  let container: ModelContainer
  let repository: SwiftDataServerPreferenceRepository
  let localProfileRepository: SwiftDataLocalProfileRepository
  let memberProvider: SignedInMemberStub
  let serverSynchronizer: ServerSynchronizerSpy
  let useCase: AccountVoiceSelectionUseCase
}

@MainActor
private final class SignedInMemberStub: SignedInMemberProviding {
  var signedInMemberID: Int64?

  init(signedInMemberID: Int64?) {
    self.signedInMemberID = signedInMemberID
  }
}

@MainActor
private final class ServerSynchronizerSpy: ServerSynchronizing {
  private(set) var calls: [(memberID: Int64, trigger: SyncTrigger)] = []
  private(set) var suspendedMemberIDs: [Int64] = []
  private(set) var resumedMemberIDs: [Int64] = []

  func synchronize(memberID: Int64, trigger: SyncTrigger) async {
    calls.append((memberID, trigger))
  }

  func suspendSynchronization(memberID: Int64) async {
    suspendedMemberIDs.append(memberID)
  }

  func resumeSynchronization(memberID: Int64) {
    resumedMemberIDs.append(memberID)
  }
}

private struct VoiceAlwaysAvailableProbe: VoiceAvailabilityProbing {
  func isAvailable(_ voice: VoiceProfile) -> Bool {
    true
  }
}

nonisolated private final class VoiceRemoteStub:
  AccountVoiceRemoteServing,
  @unchecked Sendable {
  private let lock = NSLock()
  private let fetchResult: Result<[ServerVoiceCatalogueItem], Error>
  private let updateResult: Result<AuthoritativeServerVoiceSelection, Error>
  private var updatedTtsIDs: [Int64] = []

  init(
    fetchResult: Result<[ServerVoiceCatalogueItem], Error>,
    updateResult: Result<AuthoritativeServerVoiceSelection, Error> = .failure(
      APIError.transport(code: -1009, message: "offline")
    )
  ) {
    self.fetchResult = fetchResult
    self.updateResult = updateResult
  }

  func fetchVoices(
    memberID: Int64
  ) async throws -> [ServerVoiceCatalogueItem] {
    try fetchResult.get()
  }

  func updateSelection(
    ttsID: Int64,
    memberID: Int64
  ) async throws -> AuthoritativeServerVoiceSelection {
    recordUpdatedTtsID(ttsID)
    return try updateResult.get()
  }

  private func recordUpdatedTtsID(_ ttsID: Int64) {
    lock.lock()
    updatedTtsIDs.append(ttsID)
    lock.unlock()
  }
}

nonisolated private final class VoiceAccessTokenProvider:
  AccountBoundAccessTokenProviding {
  private let context = AccountAuthorizationContext(
    memberID: 96,
    accessToken: "access-token",
    sessionID: UUID()
  )

  var accessToken: String? {
    context.accessToken
  }

  func authorizationContext(
    forMemberID memberID: Int64
  ) -> AccountAuthorizationContext? {
    context.memberID == memberID ? context : nil
  }
}

nonisolated private final class VoiceRequestCapturePlugin:
  PluginType,
  @unchecked Sendable {
  private let lock = NSLock()
  private var capturedRequest: URLRequest?

  var request: URLRequest? {
    lock.lock()
    defer { lock.unlock() }
    return capturedRequest
  }

  func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
    lock.lock()
    capturedRequest = request
    lock.unlock()
    return request
  }
}
