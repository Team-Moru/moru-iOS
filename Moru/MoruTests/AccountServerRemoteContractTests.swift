//
//  AccountServerRemoteContractTests.swift
//  MoruTests
//

import Foundation
import XCTest

import Moya

@testable import Moru

@MainActor
final class AccountServerRemoteContractTests: XCTestCase {
  func testTargetsMatchSwaggerAndSamplesDecode() throws {
    let profile = AccountServerTarget.profile
    let streak = AccountServerTarget.streak
    let voices = AccountServerTarget.voices
    let update = AccountServerTarget.updateTTS(
      TTSUpdateRequestDTO(ttsId: 2)
    )

    XCTAssertEqual(profile.path, "/members/me/profile")
    XCTAssertEqual(streak.path, "/members/me/streak")
    XCTAssertEqual(voices.path, "/tts")
    XCTAssertEqual(update.path, "/members/me/tts")
    XCTAssertEqual(profile.method, .get)
    XCTAssertEqual(streak.method, .get)
    XCTAssertEqual(voices.method, .get)
    XCTAssertEqual(update.method, .patch)

    let targets = [profile, streak, voices, update]
    XCTAssertTrue(
      targets.allSatisfy {
        $0.authenticationRequirement == .bearer
      }
    )

    for target in [profile, streak, voices] {
      guard case .requestPlain = target.task else {
        return XCTFail("Expected a body-free GET request.")
      }
    }
    guard case .requestJSONEncodable = update.task else {
      return XCTFail("Expected a JSON-encoded PATCH request.")
    }

    let decoder = JSONDecoder()
    let profileEnvelope = try decoder.decode(
      APIResponse<AccountProfileResponseDTO>.self,
      from: profile.sampleData
    )
    let streakEnvelope = try decoder.decode(
      APIResponse<AccountStreakResponseDTO>.self,
      from: streak.sampleData
    )
    let voiceEnvelope = try decoder.decode(
      APIResponse<TTSVoiceListResponseDTO>.self,
      from: voices.sampleData
    )
    let updateEnvelope = try decoder.decode(
      APIResponse<TTSUpdateResponseDTO>.self,
      from: update.sampleData
    )
    XCTAssertEqual(profileEnvelope.result?.memberId, 98)
    XCTAssertEqual(streakEnvelope.result?.weeklyStatus?.count, 7)
    XCTAssertEqual(voiceEnvelope.result?.voices?.count, 2)
    XCTAssertEqual(updateEnvelope.result?.ttsId, 2)
    XCTAssertEqual(updateEnvelope.result?.selectionVersion, 0)
  }

  func testFetchesSupportedAccountEndpointsWithExactPatchBody()
    async throws {
    let capture = AccountServerRequestCapturePlugin()
    let service = makeStubbedService(additionalPlugins: [capture])

    let profile = try await service.fetchProfile(memberID: 98)
    let streak = try await service.fetchStreak(memberID: 98)
    let voices = try await service.fetchVoices(memberID: 98)
    let selection = try await service.updateTTS(
      ttsID: 2,
      memberID: 98
    )

    XCTAssertEqual(
      profile,
      ServerAccountProfile(
        memberID: 98,
        nickname: "모루유저",
        loginType: .kakao,
        profileImageKey: nil,
        selectedTTSID: 1
      )
    )
    XCTAssertEqual(
      streak,
      ServerAccountStreak(
        currentDays: 5,
        bestDays: 12,
        weeklyStatus: [
          true,
          true,
          false,
          false,
          false,
          false,
          false,
        ]
      )
    )
    XCTAssertEqual(
      voices,
      [
        ServerTTSVoice(
          ttsID: 1,
          voiceCode: "MINSEO",
          displayName: "민서",
          description: "따뜻한 친구",
          isProOnly: false,
          previewAudioURL: URL(
            string: "https://moru-tts.s3.ap-northeast-2.amazonaws.com/previews/minseo.mp3"
          )
        ),
        ServerTTSVoice(
          ttsID: 2,
          voiceCode: "HYEONU",
          displayName: "현우",
          description: "차분한 친구",
          isProOnly: true,
          previewAudioURL: URL(
            string: "https://moru-tts.s3.ap-northeast-2.amazonaws.com/previews/hyeonu.mp3"
          )
        ),
      ]
    )
    XCTAssertEqual(
      selection,
      ServerTTSSelection(
        memberID: 98,
        ttsID: 2,
        voiceCode: "HYEONU",
        displayName: "현우",
        selectionVersion: 0
      )
    )
    let requests = capture.requests
    XCTAssertEqual(requests.count, 4)
    XCTAssertEqual(
      Set(requests.compactMap(\.url?.path)),
      Set([
        "/members/me/profile",
        "/members/me/streak",
        "/tts",
        "/members/me/tts",
      ])
    )
    XCTAssertTrue(
      requests.allSatisfy {
        $0.value(forHTTPHeaderField: "Authorization")
          == "Bearer access-token"
      }
    )

    let patchRequest = try XCTUnwrap(
      requests.first {
        $0.url?.path == "/members/me/tts"
      }
    )
    XCTAssertEqual(patchRequest.httpMethod, "PATCH")
    let body = try XCTUnwrap(patchRequest.httpBody)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: body) as? [String: Any]
    )
    XCTAssertEqual(json.count, 1)
    XCTAssertEqual(json["ttsId"] as? Int, 2)

    XCTAssertTrue(
      requests
        .filter { $0.url?.path != "/members/me/tts" }
        .allSatisfy {
          $0.httpMethod == "GET" && $0.httpBody == nil
        }
    )
  }

  func testDTOsDecodeMissingSwaggerFieldsThenMappingRejectsThem()
    async throws {
    let decoder = JSONDecoder()
    let profile = try decoder.decode(
      AccountProfileResponseDTO.self,
      from: Data("{}".utf8)
    )
    let streak = try decoder.decode(
      AccountStreakResponseDTO.self,
      from: Data("{}".utf8)
    )
    let voices = try decoder.decode(
      TTSVoiceListResponseDTO.self,
      from: Data("{}".utf8)
    )
    let legacyUpdate = try decoder.decode(
      TTSUpdateResponseDTO.self,
      from: Data(
        """
        {
          "memberId": 98,
          "ttsId": 2,
          "voiceCode": "HYEONU",
          "displayName": "현우"
        }
        """.utf8
      )
    )

    XCTAssertNil(profile.memberId)
    XCTAssertNil(streak.currentStreak)
    XCTAssertNil(voices.voices)
    XCTAssertNil(legacyUpdate.selectionVersion)

    let client = AccountServerPayloadAPIClient(
      profile: profile,
      streak: streak,
      voices: voices
    )
    let service = DefaultAccountServerRemoteService(apiClient: client)

    await assertRemoteError(.invalidResponse) {
      _ = try await service.fetchProfile(memberID: 98)
    }
    await assertRemoteError(.invalidResponse) {
      _ = try await service.fetchStreak(memberID: 98)
    }
    await assertRemoteError(.invalidResponse) {
      _ = try await service.fetchVoices(memberID: 98)
    }

    let legacyService = DefaultAccountServerRemoteService(
      apiClient: AccountServerPayloadAPIClient(update: legacyUpdate)
    )
    let legacySelection = try await legacyService.updateTTS(
      ttsID: 2,
      memberID: 98
    )
    XCTAssertNil(legacySelection.selectionVersion)
  }

  func testRejectsInvalidMemberAndTTSIDsBeforeTransport() async {
    let client = AccountServerCallCountingAPIClient()
    let service = DefaultAccountServerRemoteService(apiClient: client)

    await assertRemoteError(.invalidRequest) {
      _ = try await service.fetchProfile(memberID: 0)
    }
    await assertRemoteError(.invalidRequest) {
      _ = try await service.fetchStreak(memberID: -1)
    }
    await assertRemoteError(.invalidRequest) {
      _ = try await service.fetchVoices(memberID: 0)
    }
    await assertRemoteError(.invalidRequest) {
      _ = try await service.updateTTS(ttsID: 0, memberID: 98)
    }
    await assertRemoteError(.invalidRequest) {
      _ = try await service.updateTTS(ttsID: 1, memberID: 0)
    }

    XCTAssertEqual(client.callCount, 0)
  }

  func testProfileRequiresMatchingMemberPositiveTTSIDAndText()
    async throws {
    let invalidProfiles = [
      accountProfileDTO(memberId: 99),
      accountProfileDTO(memberId: -1),
      accountProfileDTO(nickname: "  "),
      accountProfileDTO(loginType: "\n"),
      accountProfileDTO(profileImageKey: " "),
      accountProfileDTO(ttsId: 0),
    ]

    for profile in invalidProfiles {
      let service = DefaultAccountServerRemoteService(
        apiClient: AccountServerPayloadAPIClient(profile: profile)
      )
      await assertRemoteError(.invalidResponse) {
        _ = try await service.fetchProfile(memberID: 98)
      }
    }

    let service = DefaultAccountServerRemoteService(
      apiClient: AccountServerPayloadAPIClient(
        profile: accountProfileDTO(
          nickname: "  다인  ",
          loginType: "FUTURE_PROVIDER",
          profileImageKey: " profiles/98 "
        )
      )
    )
    let profile = try await service.fetchProfile(memberID: 98)

    XCTAssertEqual(profile.nickname, "다인")
    XCTAssertEqual(
      profile.loginType,
      .unknown("FUTURE_PROVIDER")
    )
    XCTAssertEqual(profile.profileImageKey, "profiles/98")
  }

  func testStreakRequiresNonnegativeCountsAndSevenStatuses()
    async {
    let invalidStreaks = [
      accountStreakDTO(currentStreak: -1),
      accountStreakDTO(maxStreak: -1),
      accountStreakDTO(weeklyStatus: Array(repeating: false, count: 6)),
      accountStreakDTO(weeklyStatus: Array(repeating: false, count: 8)),
      AccountStreakResponseDTO(
        currentStreak: nil,
        maxStreak: 0,
        weeklyStatus: Array(repeating: false, count: 7)
      ),
    ]

    for streak in invalidStreaks {
      let service = DefaultAccountServerRemoteService(
        apiClient: AccountServerPayloadAPIClient(streak: streak)
      )
      await assertRemoteError(.invalidResponse) {
        _ = try await service.fetchStreak(memberID: 98)
      }
    }
  }

  func testVoiceListPreservesOrderAndRejectsDuplicateIDsOrBlankFields()
    async throws {
    let validVoices = TTSVoiceListResponseDTO(
      voices: [
        ttsVoiceDTO(ttsId: 2, voiceCode: " B ", displayName: " 둘째 "),
        ttsVoiceDTO(ttsId: 1, voiceCode: " A ", displayName: " 첫째 "),
      ]
    )
    let validService = DefaultAccountServerRemoteService(
      apiClient: AccountServerPayloadAPIClient(voices: validVoices)
    )

    let voices = try await validService.fetchVoices(memberID: 98)

    XCTAssertEqual(voices.map(\.ttsID), [2, 1])
    XCTAssertEqual(voices.map(\.voiceCode), ["B", "A"])
    XCTAssertEqual(voices.map(\.displayName), ["둘째", "첫째"])
    XCTAssertTrue(voices.allSatisfy { $0.previewAudioURL == nil })

    let invalidVoiceLists = [
      TTSVoiceListResponseDTO(
        voices: [
          ttsVoiceDTO(ttsId: 1),
          ttsVoiceDTO(ttsId: 1),
        ]
      ),
      TTSVoiceListResponseDTO(
        voices: [ttsVoiceDTO(previewAudioUrl: "http://audio.example.com/preview.mp3")]
      ),
      TTSVoiceListResponseDTO(voices: [ttsVoiceDTO(ttsId: 0)]),
      TTSVoiceListResponseDTO(
        voices: [ttsVoiceDTO(voiceCode: " ")]
      ),
      TTSVoiceListResponseDTO(
        voices: [ttsVoiceDTO(displayName: "\n")]
      ),
      TTSVoiceListResponseDTO(
        voices: [ttsVoiceDTO(description: "  ")]
      ),
      TTSVoiceListResponseDTO(
        voices: [
          TTSVoiceResponseDTO(
            ttsId: 1,
            voiceCode: "MINSEO",
            displayName: "민서",
            description: "친구",
            proOnly: nil
          ),
        ]
      ),
    ]

    for voiceList in invalidVoiceLists {
      let service = DefaultAccountServerRemoteService(
        apiClient: AccountServerPayloadAPIClient(voices: voiceList)
      )
      await assertRemoteError(.invalidResponse) {
        _ = try await service.fetchVoices(memberID: 98)
      }
    }

    let emptyService = DefaultAccountServerRemoteService(
      apiClient: AccountServerPayloadAPIClient(
        voices: TTSVoiceListResponseDTO(voices: [])
      )
    )
    let emptyVoices = try await emptyService.fetchVoices(memberID: 98)
    XCTAssertEqual(emptyVoices, [])
  }

  func testTTSUpdateRequiresMatchingMemberAndRequestedTTSID()
    async {
    let invalidUpdates = [
      ttsUpdateDTO(memberId: 99),
      ttsUpdateDTO(memberId: 0),
      ttsUpdateDTO(ttsId: 3),
      ttsUpdateDTO(ttsId: 0),
      ttsUpdateDTO(voiceCode: " "),
      ttsUpdateDTO(displayName: "\n"),
      ttsUpdateDTO(selectionVersion: -1),
    ]

    for update in invalidUpdates {
      let service = DefaultAccountServerRemoteService(
        apiClient: AccountServerPayloadAPIClient(update: update)
      )
      await assertRemoteError(.invalidResponse) {
        _ = try await service.updateTTS(ttsID: 2, memberID: 98)
      }
    }
  }

  func testCancellationAndAccountAuthorizationChangeRemainDistinct()
    async {
    for error in [CancellationError(), APIError.cancelled] as [any Error] {
      let service = DefaultAccountServerRemoteService(
        apiClient: AccountServerThrowingAPIClient(error: error)
      )

      do {
        _ = try await service.fetchProfile(memberID: 98)
        XCTFail("Expected cancellation.")
      } catch is CancellationError {
        continue
      } catch {
        XCTFail("Expected CancellationError, got \(error)")
      }
    }

    let changedAccountService = DefaultAccountServerRemoteService(
      apiClient: AccountServerThrowingAPIClient(
        error: AccountAuthorizationContextError.memberMismatch
      )
    )
    await assertRemoteError(.accountAuthorizationChanged) {
      _ = try await changedAccountService.fetchProfile(memberID: 98)
    }
  }

  func testCancellationAfterTransportReturnsCannotPublishPayload()
    async {
    let gate = AccountServerRequestGate()
    let service = DefaultAccountServerRemoteService(
      apiClient: AccountServerDeferredAPIClient(gate: gate)
    )
    let task = _Concurrency.Task {
      try await service.fetchProfile(memberID: 98)
    }

    await gate.waitUntilRequestArrives()
    task.cancel()
    await gate.release()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation.")
    } catch is CancellationError {
      // Expected.
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }
  }

  private func assertRemoteError(
    _ expected: AccountServerRemoteError,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected).")
    } catch let error as AccountServerRemoteError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Expected AccountServerRemoteError, got \(error)")
    }
  }

  nonisolated private func makeStubbedService(
    additionalPlugins: [any PluginType & Sendable] = []
  ) -> DefaultAccountServerRemoteService {
    let client = DefaultAPIClient(
      tokenProvider: AccountServerAccessTokenProvider(),
      providerFactory: MoyaProviderFactory(
        endpointBuilder: { target in
          let endpoint = MoyaProvider<MultiTarget>
            .defaultEndpointMapping(for: target)
          return Endpoint(
            url: endpoint.url,
            sampleResponseClosure: {
              .networkResponse(200, target.sampleData)
            },
            method: endpoint.method,
            task: endpoint.task,
            httpHeaderFields: endpoint.httpHeaderFields
          )
        },
        stubBuilder: { _ in .immediate },
        additionalPlugins: additionalPlugins
      )
    )
    return DefaultAccountServerRemoteService(apiClient: client)
  }
}

nonisolated private func accountProfileDTO(
  memberId: Int64? = 98,
  nickname: String? = "모루유저",
  loginType: String? = "KAKAO",
  profileImageKey: String? = nil,
  ttsId: Int64? = 1
) -> AccountProfileResponseDTO {
  AccountProfileResponseDTO(
    memberId: memberId,
    nickname: nickname,
    loginType: loginType,
    profileImageKey: profileImageKey,
    ttsId: ttsId
  )
}

nonisolated private func accountStreakDTO(
  currentStreak: Int64? = 5,
  maxStreak: Int64? = 12,
  weeklyStatus: [Bool]? = Array(repeating: false, count: 7)
) -> AccountStreakResponseDTO {
  AccountStreakResponseDTO(
    currentStreak: currentStreak,
    maxStreak: maxStreak,
    weeklyStatus: weeklyStatus
  )
}

nonisolated private func ttsVoiceDTO(
  ttsId: Int64? = 1,
  voiceCode: String? = "MINSEO",
  displayName: String? = "민서",
  description: String? = "따뜻한 친구",
  proOnly: Bool? = false,
  previewAudioUrl: String? = nil
) -> TTSVoiceResponseDTO {
  TTSVoiceResponseDTO(
    ttsId: ttsId,
    voiceCode: voiceCode,
    displayName: displayName,
    description: description,
    proOnly: proOnly,
    previewAudioUrl: previewAudioUrl
  )
}

nonisolated private func ttsUpdateDTO(
  memberId: Int64? = 98,
  ttsId: Int64? = 2,
  voiceCode: String? = "HYEONU",
  displayName: String? = "현우",
  selectionVersion: Int64? = nil
) -> TTSUpdateResponseDTO {
  TTSUpdateResponseDTO(
    memberId: memberId,
    ttsId: ttsId,
    voiceCode: voiceCode,
    displayName: displayName,
    selectionVersion: selectionVersion
  )
}

nonisolated private final class AccountServerAccessTokenProvider:
  AccountBoundAccessTokenProviding {
  private let context = AccountAuthorizationContext(
    memberID: 98,
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

nonisolated private final class AccountServerRequestCapturePlugin:
  PluginType,
  @unchecked Sendable {
  private let lock = NSLock()
  private var capturedRequests: [URLRequest] = []

  var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return capturedRequests
  }

  func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
    lock.lock()
    capturedRequests.append(request)
    lock.unlock()
    return request
  }
}

nonisolated private final class AccountServerPayloadAPIClient:
  AccountBoundAPIClient,
  @unchecked Sendable {
  private let profile: AccountProfileResponseDTO
  private let streak: AccountStreakResponseDTO
  private let voices: TTSVoiceListResponseDTO
  private let update: TTSUpdateResponseDTO

  init(
    profile: AccountProfileResponseDTO = accountProfileDTO(),
    streak: AccountStreakResponseDTO = accountStreakDTO(),
    voices: TTSVoiceListResponseDTO = TTSVoiceListResponseDTO(
      voices: [ttsVoiceDTO()]
    ),
    update: TTSUpdateResponseDTO = ttsUpdateDTO()
  ) {
    self.profile = profile
    self.streak = streak
    self.voices = voices
    self.update = update
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    throw APIError.invalidRequest("Expected an account-bound request.")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    guard memberID == 98,
          let target = target as? AccountServerTarget else {
      throw AccountAuthorizationContextError.memberMismatch
    }

    let response: Any
    switch target {
    case .profile:
      response = profile
    case .streak:
      response = streak
    case .voices:
      response = voices
    case .updateTTS:
      response = update
    }

    guard let payload = response as? Payload else {
      throw APIError.decoding("Unexpected account payload type.")
    }
    return payload
  }

  func requestVoid<Target: MoruTargetType>(
    _ target: Target
  ) async throws {
    throw APIError.invalidRequest("Unexpected void request.")
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    throw APIError.invalidRequest("Unexpected data request.")
  }
}

nonisolated private final class AccountServerCallCountingAPIClient:
  AccountBoundAPIClient,
  @unchecked Sendable {
  private let lock = NSLock()
  private var requestCallCount = 0

  var callCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return requestCallCount
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  func requestVoid<Target: MoruTargetType>(
    _ target: Target
  ) async throws {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  private func recordCall() {
    lock.lock()
    requestCallCount += 1
    lock.unlock()
  }
}

nonisolated private final class AccountServerThrowingAPIClient:
  AccountBoundAPIClient,
  @unchecked Sendable {
  private let error: any Error

  init(error: any Error) {
    self.error = error
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    throw error
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    throw error
  }

  func requestVoid<Target: MoruTargetType>(
    _ target: Target
  ) async throws {
    throw error
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    throw error
  }
}

nonisolated private final class AccountServerDeferredAPIClient:
  AccountBoundAPIClient,
  Sendable {
  private let gate: AccountServerRequestGate

  init(gate: AccountServerRequestGate) {
    self.gate = gate
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    throw APIError.invalidRequest("Expected an account-bound request.")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    await gate.arrive()
    let response = accountProfileDTO()
    guard let payload = response as? Payload else {
      throw APIError.decoding("Unexpected account payload type.")
    }
    return payload
  }

  func requestVoid<Target: MoruTargetType>(
    _ target: Target
  ) async throws {
    throw APIError.invalidRequest("Unexpected void request.")
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    throw APIError.invalidRequest("Unexpected data request.")
  }
}

private actor AccountServerRequestGate {
  private var requestArrived = false
  private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func arrive() async {
    requestArrived = true
    let waiters = arrivalWaiters
    arrivalWaiters.removeAll()
    waiters.forEach { $0.resume() }

    await withCheckedContinuation { continuation in
      releaseWaiters.append(continuation)
    }
  }

  func waitUntilRequestArrives() async {
    guard !requestArrived else {
      return
    }
    await withCheckedContinuation { continuation in
      arrivalWaiters.append(continuation)
    }
  }

  func release() {
    let waiters = releaseWaiters
    releaseWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }
}
