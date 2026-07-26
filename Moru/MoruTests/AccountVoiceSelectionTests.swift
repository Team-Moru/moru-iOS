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

    let voices = try await catalogueSource.fetchVoices()

    XCTAssertEqual(
      voices,
      [
        VoiceResponseDTO(
          ttsId: 1,
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
    let update = try await updateSource.updateSelection(ttsID: 1)

    XCTAssertEqual(update.memberId, 96)
    XCTAssertEqual(update.ttsId, 1)
    XCTAssertEqual(update.voiceCode, "MINSEO")
    let updateRequest = try XCTUnwrap(updateCapture.request)
    XCTAssertEqual(updateRequest.httpMethod, "PATCH")
    XCTAssertEqual(updateRequest.url?.path, "/members/me/tts")
    XCTAssertEqual(
      try jsonBody(updateRequest)["ttsId"] as? Int,
      1
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
      _ = try await malformedSource.fetchVoices()
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

    await assertError(VoiceRemoteDataSourceError.self) {
      _ = try await duplicateSource.fetchVoices()
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
    try fixture.repository.upsertCatalog(
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
    try fixture.repository.upsertCatalog(
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

    XCTAssertEqual(snapshot.options.map(\.serverVoiceCode), ["CACHED"])
    XCTAssertFalse(snapshot.options.contains { $0.serverVoiceCode == "OTHER_ACCOUNT" })
    XCTAssertNotNil(snapshot.notice)
  }

  func testProductionCompatibilityTableDoesNotInferFromMatchingDisplayName() async throws {
    let fixture = try makeFixture(
      remoteDataSource: VoiceRemoteStub(
        fetchResult: .success(
          [
            VoiceResponseDTO(
              ttsId: 1,
              voiceCode: "MINSEO",
              displayName: VoiceProfile.aoede.displayName,
              description: "Swagger example",
              proOnly: false
            ),
            VoiceResponseDTO(
              ttsId: 2,
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

    XCTAssertEqual(snapshot.options.count, 2)
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

  func testUnknownProIncompatibleAndMissingBundleOptionsAreDisabled() async throws {
    let compatibility = VoiceCompatibilityTable(
      entries: ["KNOWN_NO_AUDIO": VoiceProfile.aoede.id]
    )
    let fixture = try makeFixture(
      remoteDataSource: VoiceRemoteStub(fetchResult: .success([])),
      signedIn: true,
      compatibilityTable: compatibility
    )
    try fixture.repository.upsertCatalog(
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
    let availability = Dictionary(
      uniqueKeysWithValues: snapshot.options.compactMap { option in
        option.serverVoiceCode.map { ($0, option.availability) }
      }
    )

    XCTAssertEqual(availability["UNKNOWN_METADATA"], .unknownMetadata)
    XCTAssertEqual(availability["PRO"], .proOnly)
    XCTAssertEqual(availability["NOT_MAPPED"], .incompatible)
    XCTAssertEqual(availability["KNOWN_NO_AUDIO"], .missingBundledAudio)
    XCTAssertTrue(snapshot.options.allSatisfy { !$0.availability.isSelectable })
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
            voiceDTO(ttsID: 11, code: "TEST_AOEDE", name: "테스트 A"),
            voiceDTO(ttsID: 12, code: "TEST_CHARON", name: "테스트 B"),
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
  }

  func testExecutorReturnsSentOnlyForExactAuthoritativeResponse() async throws {
    let compatibility = VoiceCompatibilityTable(
      entries: ["TEST_AOEDE": VoiceProfile.aoede.id]
    )
    let fixture = try makeFixture(
      remoteDataSource: VoiceRemoteStub(fetchResult: .success([])),
      signedIn: true,
      compatibilityTable: compatibility
    )
    try fixture.repository.upsertCatalog(
      [
        try catalogEntry(
          memberID: Self.memberID,
          ttsID: 11,
          voiceCode: "TEST_AOEDE",
          displayName: "테스트"
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
        TtsUpdateResponseDTO(
          memberId: Self.memberID,
          ttsId: 11,
          voiceCode: "TEST_AOEDE",
          displayName: "서버 표시 이름"
        )
      )
    )
    let successExecutor = VoiceSelectionMutationExecutor(
      remoteDataSource: successRemote,
      catalogueRepository: fixture.repository,
      compatibilityTable: compatibility
    )

    let executionResult = try await successExecutor.execute(mutation)
    XCTAssertEqual(executionResult, .sent)
    let metadata = try XCTUnwrap(
      try fixture.repository.catalog(memberID: Self.memberID).first
    )
    XCTAssertTrue(
      try XCTUnwrap(
        VoiceCatalogMetadata.decode(rawValue: metadata.tierRawValue)
      ).isAuthoritativeSelection
    )

    let mismatchRemote = VoiceRemoteStub(
      fetchResult: .success([]),
      updateResult: .success(
        TtsUpdateResponseDTO(
          memberId: 999,
          ttsId: 11,
          voiceCode: "TEST_AOEDE",
          displayName: "다른 계정"
        )
      )
    )
    let mismatchExecutor = VoiceSelectionMutationExecutor(
      remoteDataSource: mismatchRemote,
      catalogueRepository: fixture.repository,
      compatibilityTable: compatibility
    )

    await assertError(VoiceRemoteDataSourceError.self) {
      _ = try await mismatchExecutor.execute(mutation)
    }
  }

  func testMismatchRequiresExplicitChoiceAndNeverOverwritesLocalOnLoad() async throws {
    let compatibility = VoiceCompatibilityTable(
      entries: [
        "TEST_AOEDE": VoiceProfile.aoede.id,
        "TEST_CHARON": VoiceProfile.charon.id,
      ]
    )
    let fixture = try makeFixture(
      remoteDataSource: VoiceRemoteStub(fetchResult: .success([])),
      signedIn: true,
      compatibilityTable: compatibility,
      selectedVoice: .aoede
    )
    try fixture.repository.upsertCatalog(
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
          [voiceDTO(ttsID: 11, code: "TEST_AOEDE", name: "테스트")]
        )
      ),
      signedIn: true,
      compatibilityTable: compatibility,
      selectedVoice: .charon
    )
    let snapshot = await fixture.useCase.loadCatalogue()
    let staleOption = try XCTUnwrap(snapshot.options.first)
    try fixture.accountSessionStore.establishSession(
      credentials: AccountCredentials(
        memberID: 97,
        accessToken: "other-access-token",
        refreshToken: "other-refresh-token",
        onboardingCompleted: true
      )
    )

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
    remoteDataSource: any VoiceRemoteDataSource,
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
    let accountSessionStore = AccountSessionStore(
      credentialStore: VoiceCredentialStore(),
      accessTokenProvider: MemoryAccessTokenProvider()
    )
    if signedIn {
      try accountSessionStore.establishSession(
        credentials: AccountCredentials(
          memberID: Self.memberID,
          accessToken: "access-token",
          refreshToken: "refresh-token",
          onboardingCompleted: true
        )
      )
    }
    let syncCoordinator = SyncCoordinator(
      mutationRepository: repository,
      executor: DeferredServerMutationExecutor()
    )
    let useCase = AccountVoiceSelectionUseCase(
      profileSettingsUseCase: profileUseCase,
      voiceAvailabilityProbe: probe,
      remoteDataSource: remoteDataSource,
      catalogueRepository: repository,
      mutationRepository: repository,
      syncCoordinator: syncCoordinator,
      accountSessionStore: accountSessionStore,
      compatibilityTable: compatibilityTable
    )
    return VoiceFixture(
      container: container,
      repository: repository,
      localProfileRepository: localProfileRepository,
      accountSessionStore: accountSessionStore,
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

  private func voiceDTO(
    ttsID: Int64,
    code: String,
    name: String
  ) -> VoiceResponseDTO {
    VoiceResponseDTO(
      ttsId: ttsID,
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
  let accountSessionStore: AccountSessionStore
  let useCase: AccountVoiceSelectionUseCase
}

private struct VoiceAlwaysAvailableProbe: VoiceAvailabilityProbing {
  func isAvailable(_ voice: VoiceProfile) -> Bool {
    true
  }
}

nonisolated private final class VoiceRemoteStub:
  VoiceRemoteDataSource,
  @unchecked Sendable {
  private let lock = NSLock()
  private let fetchResult: Result<[VoiceResponseDTO], Error>
  private let updateResult: Result<TtsUpdateResponseDTO, Error>
  private var updatedTtsIDs: [Int64] = []

  init(
    fetchResult: Result<[VoiceResponseDTO], Error>,
    updateResult: Result<TtsUpdateResponseDTO, Error> = .failure(
      APIError.transport(code: -1009, message: "offline")
    )
  ) {
    self.fetchResult = fetchResult
    self.updateResult = updateResult
  }

  func fetchVoices() async throws -> [VoiceResponseDTO] {
    try fetchResult.get()
  }

  func updateSelection(ttsID: Int64) async throws -> TtsUpdateResponseDTO {
    recordUpdatedTtsID(ttsID)
    return try updateResult.get()
  }

  private func recordUpdatedTtsID(_ ttsID: Int64) {
    lock.lock()
    updatedTtsIDs.append(ttsID)
    lock.unlock()
  }
}

nonisolated private final class VoiceCredentialStore:
  CredentialStore,
  @unchecked Sendable {
  private var credentials: AccountCredentials?

  func save(_ credentials: AccountCredentials) throws {
    self.credentials = credentials
  }

  func load() throws -> AccountCredentials? {
    credentials
  }

  func remove() throws {
    credentials = nil
  }
}

nonisolated private final class VoiceAccessTokenProvider: AccessTokenProviding {
  let accessToken: String? = "access-token"
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
