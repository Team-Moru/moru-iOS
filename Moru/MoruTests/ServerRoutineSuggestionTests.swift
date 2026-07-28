//
//  ServerRoutineSuggestionTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest

import Moya

@testable import Moru

@MainActor
final class ServerRoutineSuggestionTests: XCTestCase {
  func testTargetMatchesSwaggerUsesBearerAndRedactsSensitiveInput() throws {
    let request = RoutineGroupAiGenerateRequestDTO(
      userInput: "개인적인 아침 계획"
    )
    let target = RoutineSuggestionTarget.generate(request)

    XCTAssertEqual(target.path, "/routine-groups/ai-generate")
    XCTAssertEqual(target.method, .post)
    XCTAssertEqual(target.authenticationRequirement, .bearer)
    XCTAssertEqual(request.description, "RoutineGroupAiGenerateRequestDTO(userInput: <redacted>)")

    let adapter = MoyaTargetAdapter(
      target: target,
      baseURL: NetworkConfiguration.production.baseURL,
      requestAccessToken: "secret-access-token"
    )
    let message = NetworkLogPlugin.requestMessage(for: adapter)

    XCTAssertEqual(message, "➡️ POST /routine-groups/ai-generate")
    XCTAssertFalse(message.contains(request.userInput))
    XCTAssertFalse(message.contains("secret-access-token"))
  }

  func testRemoteDataSourceSendsOnlyBoundedTypedInputAndDecodesSwaggerResponse()
    async throws {
    let capture = RoutineSuggestionRequestCapturePlugin()
    let source = DefaultRoutineSuggestionRemoteDataSource(
      apiClient: makeClient(
        data: validResponseData(),
        additionalPlugins: [capture]
      )
    )
    let input = String(repeating: "가", count: 200)

    let response = try await source.generate(
      request: RoutineGroupAiGenerateRequestDTO(userInput: input)
    )

    XCTAssertEqual(response.title, "서버 활력 루틴")
    XCTAssertEqual(response.routines.map(\.type), ["CHECK", "TIMER", "INPUT"])

    let urlRequest = try XCTUnwrap(capture.request)
    XCTAssertEqual(urlRequest.httpMethod, "POST")
    XCTAssertEqual(urlRequest.url?.path, "/routine-groups/ai-generate")
    XCTAssertEqual(
      urlRequest.value(forHTTPHeaderField: "Authorization"),
      "Bearer access-token"
    )
    let body = try jsonBody(urlRequest)
    XCTAssertEqual(body.keys.sorted(), ["userInput"])
    XCTAssertEqual(body["userInput"] as? String, input)
    XCTAssertNil(body["voice"])
    XCTAssertNil(body["transcript"])
    XCTAssertNil(body["alarmTime"])
    XCTAssertNil(body["weekdays"])
  }

  func testServerServiceValidatesAndCreatesFreshEditableLocalDrafts()
    async throws {
    let remote = RoutineSuggestionRemoteStub(
      result: .success(validResponse())
    )
    let date = Date(timeIntervalSince1970: 1_000)
    let service = ServerRoutineSuggestionService(
      remoteDataSource: remote,
      now: { date }
    )
    let input = RoutineSuggestionInput(
      experience: .wantsRecommendation,
      routineName: "로컬 입력 이름",
      goalTags: ["health"],
      selectedKeywords: ["물 마시기"],
      freeformText: "가볍게 시작하고 싶어요",
      wakeUpHour: 6,
      wakeUpMinute: 35,
      weekdays: [.tuesday, .thursday]
    )

    let first = try await service.makeRoutine(from: input)
    let second = try await service.makeRoutine(from: input)

    XCTAssertEqual(first.name, "서버 활력 루틴")
    XCTAssertEqual(first.summary, "서버가 만든 설명")
    XCTAssertEqual(first.goalTags, input.goalTags)
    XCTAssertEqual(first.steps.map(\.type), [.confirm, .timer, .input])
    XCTAssertEqual(first.steps.map(\.estimatedSeconds), [60, 180, 90])
    XCTAssertTrue(first.steps.allSatisfy { $0.presetItemID == nil })
    XCTAssertEqual(first.alarmSchedule?.hour, input.wakeUpHour)
    XCTAssertEqual(first.alarmSchedule?.minute, input.wakeUpMinute)
    XCTAssertEqual(first.alarmSchedule?.weekdays, input.weekdays)
    XCTAssertEqual(first.sync?.status, .localOnly)
    XCTAssertEqual(first.createdAt, date)
    XCTAssertNotEqual(first.id, second.id)
    XCTAssertNotEqual(first.alarmSchedule?.id, second.alarmSchedule?.id)
    XCTAssertTrue(
      Set(first.steps.map(\.id)).isDisjoint(with: Set(second.steps.map(\.id)))
    )
  }

  func testSignedInUsesServerAndSignedOutUsesLocalFallback() async throws {
    let account = MutableRoutineSuggestionAccount(memberID: 98)
    let serverRoutine = makeRoutine(name: "서버 루틴")
    let local = RoutineSuggestionLocalStub()
    let coordinator = RoutineSuggestionCoordinator(
      serverService: RoutineSuggestionServerStub(result: .success(serverRoutine)),
      localService: local,
      accountProvider: account
    )

    let server = try await coordinator.suggest(from: input())
    XCTAssertEqual(server.routine.id, serverRoutine.id)
    XCTAssertEqual(server.source, .server)
    XCTAssertEqual(local.callCount, 0)

    account.memberID = nil
    let fallback = try await coordinator.suggest(from: input())
    XCTAssertEqual(fallback.source, .localFallback(.signedOut))
    XCTAssertEqual(local.callCount, 1)
  }

  func testAirplaneTimeoutFiveHundredMalformedAndInvalidPayloadUseLocalFallback()
    async throws {
    let failures: [(any ServerRoutineSuggestionServing, RoutineSuggestionFallbackReason)] = [
      (
        RoutineSuggestionServerStub(
          result: .failure(
            APIError.transport(
              code: URLError.notConnectedToInternet.rawValue,
              message: "offline"
            )
          )
        ),
        .offline
      ),
      (
        RoutineSuggestionServerStub(
          result: .failure(
            APIError.transport(
              code: URLError.timedOut.rawValue,
              message: "timeout"
            )
          )
        ),
        .timeout
      ),
      (
        RoutineSuggestionServerStub(
          result: .failure(
            APIError.server(
              statusCode: 503,
              code: "COMMON500",
              message: "unavailable"
            )
          )
        ),
        .serverUnavailable
      ),
      (
        ServerRoutineSuggestionService(
          remoteDataSource: DefaultRoutineSuggestionRemoteDataSource(
            apiClient: makeClient(data: Data("{malformed".utf8))
          )
        ),
        .invalidResponse
      ),
      (
        ServerRoutineSuggestionService(
          remoteDataSource: RoutineSuggestionRemoteStub(
            result: .success(
              RoutineGroupAiGenerateResponseDTO(
                title: "잘못된 루틴",
                description: nil,
                routines: [
                  RoutineSuggestionStepDTO(
                    title: "단계",
                    type: "UNKNOWN",
                    durationSecond: 60
                  )
                ]
              )
            )
          )
        ),
        .invalidResponse
      ),
    ]

    for (server, reason) in failures {
      let local = RoutineSuggestionLocalStub()
      let account = MutableRoutineSuggestionAccount(memberID: 98)
      let coordinator = RoutineSuggestionCoordinator(
        serverService: server,
        localService: local,
        accountProvider: account
      )

      let result = try await coordinator.suggest(from: input())

      XCTAssertEqual(result.source, .localFallback(reason))
      XCTAssertEqual(result.routine.name, "로컬 fallback")
      XCTAssertEqual(local.callCount, 1)
    }
  }

  func testInvalidTitleDurationAndStepCountAreRejected() async {
    let invalidResponses = [
      RoutineGroupAiGenerateResponseDTO(
        title: "   ",
        description: nil,
        routines: [
          RoutineSuggestionStepDTO(
            title: "단계",
            type: "CHECK",
            durationSecond: 60
          )
        ]
      ),
      RoutineGroupAiGenerateResponseDTO(
        title: "루틴",
        description: nil,
        routines: [
          RoutineSuggestionStepDTO(
            title: "단계",
            type: "TIMER",
            durationSecond: 0
          )
        ]
      ),
      RoutineGroupAiGenerateResponseDTO(
        title: "루틴",
        description: nil,
        routines: [
          RoutineSuggestionStepDTO(
            title: "   ",
            type: "CHECK",
            durationSecond: 60
          )
        ]
      ),
      RoutineGroupAiGenerateResponseDTO(
        title: "루틴",
        description: nil,
        routines: []
      ),
    ]

    for response in invalidResponses {
      let service = ServerRoutineSuggestionService(
        remoteDataSource: RoutineSuggestionRemoteStub(
          result: .success(response)
        )
      )

      do {
        _ = try await service.makeRoutine(from: input())
        XCTFail("Expected server validation failure")
      } catch is ServerRoutineSuggestionError {
        continue
      } catch {
        XCTFail("Expected ServerRoutineSuggestionError, got \(error)")
      }
    }
  }

  func testAccountSwitchDiscardsStaleServerResponseAndUsesLocalDraft()
    async throws {
    let account = MutableRoutineSuggestionAccount(memberID: 98)
    let gate = RoutineSuggestionServerGate()
    let local = RoutineSuggestionLocalStub()
    let coordinator = RoutineSuggestionCoordinator(
      serverService: GatedRoutineSuggestionServer(gate: gate),
      localService: local,
      accountProvider: account
    )
    let task: _Concurrency.Task<RoutineSuggestionResult, Error> =
      _Concurrency.Task {
      try await coordinator.suggest(from: input())
      }

    await gate.waitUntilRequested()
    account.memberID = 1_098
    await gate.finish(with: makeRoutine(name: "이전 계정 서버 루틴"))
    let result = try await task.value

    XCTAssertEqual(result.source, .localFallback(.accountChanged))
    XCTAssertEqual(result.routine.name, "로컬 fallback")
    XCTAssertNotEqual(result.routine.name, "이전 계정 서버 루틴")
  }

  func testSuggestionDoesNotWriteSwiftDataBeforeConfirmationAndSavesSameDraftID()
    async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(
      modelContext: container.mainContext
    )
    let preview = makeRoutine(
      name: "확인 대기 초안",
      hour: 5,
      minute: 45,
      weekdays: [.monday, .friday]
    )

    XCTAssertTrue(try dependencies.routineRepository.fetchRoutines().isEmpty)
    XCTAssertNil(try dependencies.localProfileRepository.fetchProfile())

    let useCase = CompleteOnboardingUseCase(
      onboardingRepository: dependencies.onboardingRepository,
      routineSuggestionService: dependencies.routineSuggestionService
    )
    let result = try await useCase.execute(
      CompleteOnboardingRequest(
        suggestionInput: input(
          hour: 5,
          minute: 45,
          weekdays: [.monday, .friday]
        ),
        selectedVoice: .aoede,
        previewRoutine: preview
      )
    )

    XCTAssertEqual(result.routine.id, preview.id)
    XCTAssertEqual(result.routine.steps.map(\.id), preview.steps.map(\.id))
    XCTAssertEqual(
      try dependencies.routineRepository.fetchRoutines().map(\.id),
      [preview.id]
    )
  }

  func testViewModelPreservesLocalInputAndExposesSuggestionSource() async {
    let originalDraft = OnboardingDraft(
      selectedGoalTags: ["mind"],
      selectedKeywords: ["명상"],
      freeformText: "조용히 시작하고 싶어요",
      alarmHour: 6,
      alarmMinute: 20,
      selectedWeekdays: [.wednesday, .saturday]
    )
    let account = MutableRoutineSuggestionAccount(memberID: 98)
    let coordinator = RoutineSuggestionCoordinator(
      serverService: RoutineSuggestionServerStub(
        result: .success(
          makeRoutine(
            name: "서버 초안",
            hour: 6,
            minute: 20,
            weekdays: [.wednesday, .saturday]
          )
        )
      ),
      localService: RoutineSuggestionLocalStub(),
      accountProvider: account
    )
    let viewModel = OnboardingViewModel(
      draft: originalDraft,
      routineSuggestionService: RoutineSuggestionLocalStub(),
      routineSuggestionCoordinator: coordinator
    )

    let refreshed = await viewModel.refreshPreviewAsync()
    XCTAssertTrue(refreshed)

    XCTAssertEqual(viewModel.draft.selectedGoalTags, originalDraft.selectedGoalTags)
    XCTAssertEqual(viewModel.draft.selectedKeywords, originalDraft.selectedKeywords)
    XCTAssertEqual(viewModel.draft.freeformText, originalDraft.freeformText)
    XCTAssertEqual(viewModel.draft.alarmHour, originalDraft.alarmHour)
    XCTAssertEqual(viewModel.draft.alarmMinute, originalDraft.alarmMinute)
    XCTAssertEqual(viewModel.draft.selectedWeekdays, originalDraft.selectedWeekdays)
    XCTAssertEqual(viewModel.draft.suggestionSource, .server)
    XCTAssertEqual(
      viewModel.draft.previewRoutine?.alarmSchedule?.weekdays,
      originalDraft.orderedWeekdays
    )
  }

  private func input(
    hour: Int = 6,
    minute: Int = 30,
    weekdays: [Weekday] = [.monday, .wednesday]
  ) -> RoutineSuggestionInput {
    RoutineSuggestionInput(
      experience: .wantsRecommendation,
      goalTags: ["health"],
      selectedKeywords: ["물 마시기"],
      freeformText: "가볍게 시작하고 싶어요",
      wakeUpHour: hour,
      wakeUpMinute: minute,
      weekdays: weekdays
    )
  }

  private func makeRoutine(
    name: String,
    hour: Int = 6,
    minute: Int = 30,
    weekdays: [Weekday] = [.monday, .wednesday]
  ) -> Routine {
    Routine(
      name: name,
      steps: [
        RoutineStep(
          type: .confirm,
          title: "물 마시기",
          order: 0,
          estimatedSeconds: 60
        )
      ],
      alarmSchedule: AlarmSchedule(
        hour: hour,
        minute: minute,
        weekdays: weekdays
      )
    )
  }

  private func validResponse() -> RoutineGroupAiGenerateResponseDTO {
    RoutineGroupAiGenerateResponseDTO(
      title: "서버 활력 루틴",
      description: "서버가 만든 설명",
      routines: [
        RoutineSuggestionStepDTO(
          title: "물 마시기",
          type: "CHECK",
          durationSecond: 60
        ),
        RoutineSuggestionStepDTO(
          title: "스트레칭",
          type: "TIMER",
          durationSecond: 180
        ),
        RoutineSuggestionStepDTO(
          title: "오늘의 다짐",
          type: "INPUT",
          durationSecond: 90
        ),
      ]
    )
  }

  nonisolated private func validResponseData() -> Data {
    Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": {
          "title": "서버 활력 루틴",
          "description": "서버가 만든 설명",
          "routines": [
            {"title": "물 마시기", "type": "CHECK", "durationSecond": 60},
            {"title": "스트레칭", "type": "TIMER", "durationSecond": 180},
            {"title": "오늘의 다짐", "type": "INPUT", "durationSecond": 90}
          ]
        }
      }
      """.utf8
    )
  }

  nonisolated private func makeClient(
    statusCode: Int = 200,
    data: Data,
    additionalPlugins: [any PluginType & Sendable] = []
  ) -> DefaultAPIClient {
    DefaultAPIClient(
      tokenProvider: RoutineSuggestionAccessTokenProvider(),
      providerFactory: MoyaProviderFactory(
        endpointBuilder: { target in
          let endpoint = MoyaProvider<MultiTarget>.defaultEndpointMapping(
            for: target
          )
          return Endpoint(
            url: endpoint.url,
            sampleResponseClosure: {
              .networkResponse(statusCode, data)
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
  }

  private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try XCTUnwrap(request.httpBody)
    return try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
  }
}

@MainActor
private final class MutableRoutineSuggestionAccount:
  RoutineSuggestionAccountProviding {
  var memberID: Int64?

  init(memberID: Int64?) {
    self.memberID = memberID
  }

  var routineSuggestionMemberID: Int64? {
    memberID
  }
}

@MainActor
private final class RoutineSuggestionLocalStub: RoutineSuggestionService {
  private(set) var callCount = 0

  func makeRoutine(from input: RoutineSuggestionInput) throws -> Routine {
    callCount += 1
    return Routine(
      name: "로컬 fallback",
      goalTags: input.goalTags,
      steps: [
        RoutineStep(
          type: .confirm,
          title: "로컬 단계",
          order: 0,
          estimatedSeconds: 60
        )
      ],
      alarmSchedule: AlarmSchedule(
        hour: input.wakeUpHour,
        minute: input.wakeUpMinute,
        weekdays: input.weekdays
      )
    )
  }
}

@MainActor
private final class RoutineSuggestionServerStub:
  ServerRoutineSuggestionServing {
  private let result: Result<Routine, Error>

  init(result: Result<Routine, Error>) {
    self.result = result
  }

  func makeRoutine(from input: RoutineSuggestionInput) async throws -> Routine {
    try result.get()
  }
}

nonisolated private final class RoutineSuggestionRemoteStub:
  RoutineSuggestionRemoteDataSource,
  @unchecked Sendable {
  private let result: Result<RoutineGroupAiGenerateResponseDTO, Error>

  init(result: Result<RoutineGroupAiGenerateResponseDTO, Error>) {
    self.result = result
  }

  func generate(
    request: RoutineGroupAiGenerateRequestDTO
  ) async throws -> RoutineGroupAiGenerateResponseDTO {
    try result.get()
  }
}

private actor RoutineSuggestionServerGate {
  private var requested = false
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []
  private var result: Routine?
  private var resultWaiter: CheckedContinuation<Routine, Never>?

  func waitForResult() async -> Routine {
    requested = true
    requestWaiters.forEach { $0.resume() }
    requestWaiters.removeAll()

    if let result {
      return result
    }

    return await withCheckedContinuation { continuation in
      resultWaiter = continuation
    }
  }

  func waitUntilRequested() async {
    guard !requested else {
      return
    }

    await withCheckedContinuation { continuation in
      requestWaiters.append(continuation)
    }
  }

  func finish(with routine: Routine) {
    if let resultWaiter {
      self.resultWaiter = nil
      resultWaiter.resume(returning: routine)
    } else {
      result = routine
    }
  }
}

@MainActor
private final class GatedRoutineSuggestionServer:
  ServerRoutineSuggestionServing {
  private let gate: RoutineSuggestionServerGate

  init(gate: RoutineSuggestionServerGate) {
    self.gate = gate
  }

  func makeRoutine(from input: RoutineSuggestionInput) async throws -> Routine {
    await gate.waitForResult()
  }
}

nonisolated private final class RoutineSuggestionAccessTokenProvider:
  AccessTokenProviding {
  let accessToken: String? = "access-token"
}

nonisolated private final class RoutineSuggestionRequestCapturePlugin:
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
