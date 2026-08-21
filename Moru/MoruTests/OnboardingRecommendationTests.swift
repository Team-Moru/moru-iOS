//
//  OnboardingRecommendationTests.swift
//  MoruTests
//

import Foundation
import XCTest

import Moya

@testable import Moru

@MainActor
final class OnboardingRecommendationTests: XCTestCase {
  func testTargetAndGoalMappingMatchSwagger() throws {
    let cases: [
      (
        OnboardingRecommendationGoal,
        OnboardingRecommendationGoalType,
        String
      )
    ] = [
      (.energy, .vitality, "VITALITY"),
      (.health, .health, "HEALTH"),
      (.mind, .stability, "STABILITY"),
      (.habit, .habit, "HABIT"),
    ]

    for (goal, goalType, queryValue) in cases {
      XCTAssertEqual(
        OnboardingRecommendationGoalType(goal: goal),
        goalType
      )

      let target = OnboardingRecommendationTarget.recommendations(
        goalType: goalType
      )
      XCTAssertEqual(target.path, "/onboarding/recommendations")
      XCTAssertEqual(target.method, .get)
      XCTAssertEqual(target.authenticationRequirement, .bearer)

      guard case .requestParameters(let parameters, _) = target.task else {
        return XCTFail("Expected a query-string request.")
      }
      XCTAssertEqual(parameters["goalType"] as? String, queryValue)
      XCTAssertEqual(parameters.count, 1)
    }
  }

  func testRemoteDataSourceUsesAccountBoundGETAndDecodesOptionalFields()
    async throws {
    let capture = OnboardingRecommendationRequestCapturePlugin()
    let source = DefaultOnboardingRecommendationRemoteDataSource(
      apiClient: makeClient(
        data: recommendationResponseData,
        additionalPlugins: [capture]
      )
    )

    let responses = try await source.fetchRecommendations(
      for: .mind,
      memberID: 98
    )

    XCTAssertEqual(responses.count, 2)
    XCTAssertEqual(responses[0].title, "")
    XCTAssertTrue(responses[0].steps.isEmpty)
    XCTAssertEqual(responses[1].title, "서버 마음 루틴")
    XCTAssertEqual(
      responses[1].steps.map(\.kind),
      [.check, .timer, .input]
    )
    XCTAssertEqual(
      responses[1].steps.map(\.durationSeconds),
      [60, 180, 90]
    )

    let request = try XCTUnwrap(capture.request)
    XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertEqual(request.url?.path, "/onboarding/recommendations")
    XCTAssertEqual(
      URLComponents(
        url: try XCTUnwrap(request.url),
        resolvingAgainstBaseURL: false
      )?.queryItems,
      [URLQueryItem(name: "goalType", value: "STABILITY")]
    )
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Authorization"),
      "Bearer access-token"
    )
  }

  func testServerServiceSkipsInvalidGroupAndCreatesEditableLocalDraft()
    async throws {
    let date = Date(timeIntervalSince1970: 2_000)
    let service = ServerOnboardingRecommendationService(
      remoteDataSource: OnboardingRecommendationRemoteStub(
        result: .success([
          invalidServerResponse,
          validServerResponse,
        ])
      ),
      now: { date }
    )
    let input = suggestionInput

    let routine = try await service.makeRoutine(
      from: input,
      goal: .health,
      memberID: 98
    )

    XCTAssertEqual(routine.name, "서버 건강 루틴")
    XCTAssertEqual(routine.summary, "서버 추천 설명")
    XCTAssertEqual(routine.goalTags, input.goalTags)
    XCTAssertEqual(routine.steps.map(\.type), [.confirm, .timer, .input])
    XCTAssertEqual(routine.steps.map(\.instruction), ["", "", ""])
    XCTAssertEqual(routine.alarmSchedule?.hour, input.wakeUpHour)
    XCTAssertEqual(routine.alarmSchedule?.minute, input.wakeUpMinute)
    XCTAssertEqual(routine.alarmSchedule?.weekdays, input.weekdays)
    XCTAssertEqual(routine.createdAt, date)
    XCTAssertEqual(routine.updatedAt, date)
    XCTAssertEqual(routine.sync?.status, .localOnly)
    XCTAssertNil(routine.sync?.remoteID)
    XCTAssertTrue(routine.steps.allSatisfy { $0.presetItemID == nil })
  }

  func testEmptyAndAllInvalidResponsesUseLocalFallbackWithoutRetry()
    async throws {
    for responses in [
      [ServerRoutineSuggestionResponse](),
      [invalidServerResponse],
    ] {
      let local = OnboardingRecommendationLocalStub()
      let account = MutableOnboardingRecommendationAccount(memberID: 98)
      let coordinator = OnboardingRecommendationCoordinator(
        serverService: ServerOnboardingRecommendationService(
          remoteDataSource: OnboardingRecommendationRemoteStub(
            result: .success(responses)
          )
        ),
        localService: local,
        signedInMemberProvider: account,
        geminiDataConsent: GeminiDataConsentStub()
      )

      let result = try await coordinator.suggest(from: suggestionInput)

      XCTAssertEqual(result.source, .localFallback(.serverUnavailable))
      XCTAssertEqual(result.routine.name, "로컬 fallback")
      XCTAssertEqual(local.callCount, 1)
    }
  }

  func testUndecidedGeminiConsentHoldsThenResumesServerRecommendation()
    async throws {
    let account = MutableOnboardingRecommendationAccount(memberID: 98)
    let local = OnboardingRecommendationLocalStub()
    let server = OnboardingRecommendationServerStub(
      result: .success(serverRoutine)
    )
    let consent = GeminiDataConsentStub(status: .undecided)
    let coordinator = OnboardingRecommendationCoordinator(
      serverService: server,
      localService: local,
      signedInMemberProvider: account,
      geminiDataConsent: consent
    )

    let task = _Concurrency.Task {
      try await coordinator.suggest(from: suggestionInput)
    }

    try await waitUntil {
      consent.requestCount == 1
    }

    XCTAssertEqual(local.callCount, 0)
    XCTAssertEqual(server.callCount, 0)

    consent.grant()
    let result = try await task.value

    XCTAssertEqual(result.source, .server)
    XCTAssertEqual(result.routine.name, serverRoutine.name)
    XCTAssertEqual(local.callCount, 0)
    XCTAssertEqual(server.callCount, 1)
  }

  func testDeclinedGeminiConsentUsesExplicitLocalRecommendation()
    async throws {
    let account = MutableOnboardingRecommendationAccount(memberID: 98)
    let local = OnboardingRecommendationLocalStub()
    let server = OnboardingRecommendationServerStub(
      result: .success(serverRoutine)
    )
    let consent = GeminiDataConsentStub(status: .declined)
    let coordinator = OnboardingRecommendationCoordinator(
      serverService: server,
      localService: local,
      signedInMemberProvider: account,
      geminiDataConsent: consent
    )

    let result = try await coordinator.suggest(from: suggestionInput)

    XCTAssertEqual(result.source, .localFallback(.geminiConsentDeclined))
    XCTAssertEqual(result.routine.name, "로컬 fallback")
    XCTAssertEqual(local.callCount, 1)
    XCTAssertEqual(server.callCount, 0)
    XCTAssertEqual(consent.requestCount, 0)
  }

  func testDeferringGeminiConsentDoesNotFallbackOnboardingRecommendation()
    async throws {
    let account = MutableOnboardingRecommendationAccount(memberID: 98)
    let local = OnboardingRecommendationLocalStub()
    let server = OnboardingRecommendationServerStub(
      result: .success(serverRoutine)
    )
    let consent = GeminiDataConsentStub(status: .undecided)
    let coordinator = OnboardingRecommendationCoordinator(
      serverService: server,
      localService: local,
      signedInMemberProvider: account,
      geminiDataConsent: consent
    )
    let task = _Concurrency.Task {
      try await coordinator.suggest(from: suggestionInput)
    }

    try await waitUntil {
      consent.requestCount == 1
    }
    consent.dismissConsentChoices()

    do {
      _ = try await task.value
      XCTFail("Expected a deferred-consent error without a recommendation.")
    } catch let error as RoutineSuggestionRequestError {
      XCTAssertEqual(error, .geminiConsentDeferred)
    } catch {
      XCTFail("Expected RoutineSuggestionRequestError, got \(error)")
    }

    XCTAssertEqual(local.callCount, 0)
    XCTAssertEqual(server.callCount, 0)
    XCTAssertEqual(consent.geminiDataConsentStatus, .undecided)
  }

  func testTransientFailureRetriesOnceThenSucceedsWithoutOverlap()
    async throws {
    let clock = ManualOnboardingRecommendationClock()
    let diagnostics = OnboardingRecommendationDiagnosticsSpy()
    let local = OnboardingRecommendationLocalStub()
    let account = MutableOnboardingRecommendationAccount(memberID: 98)
    let server = SequencedOnboardingRecommendationServerStub(
      results: [
        .failure(RoutineSuggestionRemoteFailure.timeout),
        .success(serverRoutine),
      ]
    )
    let coordinator = OnboardingRecommendationCoordinator(
      serverService: server,
      localService: local,
      signedInMemberProvider: account,
      geminiDataConsent: GeminiDataConsentStub(),
      clock: clock,
      diagnostics: diagnostics
    )

    let task = _Concurrency.Task {
      try await coordinator.suggest(from: suggestionInput)
    }
    try await waitUntil {
      server.callCount == 1
        && clock.pendingDeadlines.contains(.milliseconds(500))
    }

    XCTAssertEqual(server.callCount, 1)
    clock.advance(by: .milliseconds(500))
    let result = try await task.value

    XCTAssertEqual(result.source, .server)
    XCTAssertEqual(result.routine.name, serverRoutine.name)
    XCTAssertEqual(server.callCount, 2)
    XCTAssertEqual(server.maximumConcurrentCallCount, 1)
    XCTAssertEqual(local.callCount, 0)
    XCTAssertEqual(clock.now(), .milliseconds(500))
    XCTAssertTrue(diagnostics.events.contains(.retryScheduled))
    XCTAssertTrue(diagnostics.events.contains(.retryStarted))
    XCTAssertTrue(diagnostics.events.contains(.serverSucceeded))
  }

  func testSecondTransientFailureFallsBackAfterSingleRetry()
    async throws {
    let clock = ManualOnboardingRecommendationClock()
    let local = OnboardingRecommendationLocalStub()
    let account = MutableOnboardingRecommendationAccount(memberID: 98)
    let server = SequencedOnboardingRecommendationServerStub(
      results: [
        .failure(RoutineSuggestionRemoteFailure.offline),
        .failure(RoutineSuggestionRemoteFailure.serverUnavailable),
      ]
    )
    let coordinator = OnboardingRecommendationCoordinator(
      serverService: server,
      localService: local,
      signedInMemberProvider: account,
      geminiDataConsent: GeminiDataConsentStub(),
      clock: clock
    )

    let task = _Concurrency.Task {
      try await coordinator.suggest(from: suggestionInput)
    }
    try await waitUntil {
      server.callCount == 1
        && clock.pendingDeadlines.contains(.milliseconds(500))
    }
    clock.advance(by: .milliseconds(500))

    let result = try await task.value

    XCTAssertEqual(result.source, .localFallback(.serverUnavailable))
    XCTAssertEqual(result.routine.name, "로컬 fallback")
    XCTAssertEqual(server.callCount, 2)
    XCTAssertEqual(server.maximumConcurrentCallCount, 1)
    XCTAssertEqual(local.callCount, 1)
  }

  func testAccountChangeDuringRetryDelayPreventsStaleRetry()
    async throws {
    let clock = ManualOnboardingRecommendationClock()
    let local = OnboardingRecommendationLocalStub()
    let account = MutableOnboardingRecommendationAccount(memberID: 98)
    let server = SequencedOnboardingRecommendationServerStub(
      results: [
        .failure(RoutineSuggestionRemoteFailure.offline),
        .success(serverRoutine),
      ]
    )
    let coordinator = OnboardingRecommendationCoordinator(
      serverService: server,
      localService: local,
      signedInMemberProvider: account,
      geminiDataConsent: GeminiDataConsentStub(),
      clock: clock
    )

    let task = _Concurrency.Task {
      try await coordinator.suggest(from: suggestionInput)
    }
    try await waitUntil {
      server.callCount == 1
        && clock.pendingDeadlines.contains(.milliseconds(500))
    }
    account.memberID = 99
    clock.advance(by: .milliseconds(500))

    do {
      _ = try await task.value
      XCTFail("Expected the changed account to prevent the retry.")
    } catch let error as RoutineSuggestionRequestError {
      XCTAssertEqual(error, .accountChanged)
    } catch {
      XCTFail("Expected RoutineSuggestionRequestError, got \(error)")
    }

    XCTAssertEqual(server.callCount, 1)
    XCTAssertEqual(local.callCount, 0)
  }

  func testEightSecondDeadlineFallsBackWithoutWaitingInRealTime()
    async throws {
    let clock = ManualOnboardingRecommendationClock()
    let diagnostics = OnboardingRecommendationDiagnosticsSpy()
    let local = OnboardingRecommendationLocalStub()
    let server = HangingOnboardingRecommendationServerStub()
    let account = MutableOnboardingRecommendationAccount(memberID: 98)
    let coordinator = OnboardingRecommendationCoordinator(
      serverService: server,
      localService: local,
      signedInMemberProvider: account,
      geminiDataConsent: GeminiDataConsentStub(),
      clock: clock,
      diagnostics: diagnostics
    )

    let task = _Concurrency.Task {
      try await coordinator.suggest(from: suggestionInput)
    }
    try await waitUntil {
      server.callCount == 1
        && clock.pendingDeadlines.contains(.seconds(8))
    }

    clock.advance(by: .seconds(7) + .milliseconds(999))
    XCTAssertEqual(local.callCount, 0)
    XCTAssertEqual(server.callCount, 1)

    clock.advance(by: .milliseconds(1))
    let result = try await task.value

    XCTAssertEqual(clock.now(), .seconds(8))
    XCTAssertEqual(result.source, .localFallback(.serverUnavailable))
    XCTAssertEqual(local.callCount, 1)
    XCTAssertTrue(diagnostics.events.contains(.deadlineExceeded))
    XCTAssertTrue(diagnostics.events.contains(.localFallback))
  }

  func testDeadlineWinsAgainstCancellationIgnoringServerAndLateResultIsIgnored()
    async throws {
    let clock = ManualOnboardingRecommendationClock()
    let diagnostics = OnboardingRecommendationDiagnosticsSpy()
    let local = OnboardingRecommendationLocalStub()
    let account = MutableOnboardingRecommendationAccount(memberID: 98)
    let gate = OnboardingRecommendationServerGate()
    let server = GatedOnboardingRecommendationServer(gate: gate)
    let coordinator = OnboardingRecommendationCoordinator(
      serverService: server,
      localService: local,
      signedInMemberProvider: account,
      geminiDataConsent: GeminiDataConsentStub(),
      clock: clock,
      diagnostics: diagnostics
    )

    let task = _Concurrency.Task {
      try await coordinator.suggest(from: suggestionInput)
    }
    await gate.waitUntilRequested()
    try await waitUntil {
      clock.pendingDeadlines.contains(.seconds(8))
    }

    clock.advance(by: .seconds(7) + .milliseconds(999))
    XCTAssertEqual(local.callCount, 0)

    clock.advance(by: .milliseconds(1))
    let result = try await task.value

    XCTAssertEqual(clock.now(), .seconds(8))
    XCTAssertEqual(result.source, .localFallback(.serverUnavailable))
    XCTAssertEqual(local.callCount, 1)
    XCTAssertEqual(server.callCount, 1)
    XCTAssertEqual(server.completionCount, 0)
    XCTAssertTrue(diagnostics.events.contains(.deadlineExceeded))
    XCTAssertFalse(diagnostics.events.contains(.serverSucceeded))

    var repeatedResult: RoutineSuggestionResult?
    let repeatedTask = _Concurrency.Task {
      repeatedResult = try? await coordinator.suggest(from: suggestionInput)
    }
    try await waitUntil {
      repeatedResult != nil || server.callCount > 1
    }

    XCTAssertEqual(server.callCount, 1)
    XCTAssertEqual(
      repeatedResult?.source,
      .localFallback(.serverUnavailable)
    )

    await gate.finish(with: serverRoutine)
    try await waitUntil {
      server.completionCount >= 1
    }
    repeatedTask.cancel()
    _ = await repeatedTask.result

    XCTAssertEqual(local.callCount, 1)
    XCTAssertEqual(server.completionCount, 1)
    XCTAssertFalse(diagnostics.events.contains(.serverSucceeded))
  }

  func testNonTransientFailureFallsBackWithoutRetry() async throws {
    for failure in [
      RoutineSuggestionRemoteFailure.invalidResponse,
      RoutineSuggestionRemoteFailure.unavailable,
    ] {
      let clock = ManualOnboardingRecommendationClock()
      let local = OnboardingRecommendationLocalStub()
      let server = SequencedOnboardingRecommendationServerStub(
        results: [.failure(failure)]
      )
      let account = MutableOnboardingRecommendationAccount(memberID: 98)
      let coordinator = OnboardingRecommendationCoordinator(
        serverService: server,
        localService: local,
        signedInMemberProvider: account,
        geminiDataConsent: GeminiDataConsentStub(),
        clock: clock
      )

      let result = try await coordinator.suggest(from: suggestionInput)

      XCTAssertEqual(result.source, .localFallback(.serverUnavailable))
      XCTAssertEqual(server.callCount, 1)
      XCTAssertEqual(local.callCount, 1)
      XCTAssertEqual(clock.now(), .zero)
    }
  }

  func testCancellingOnlyWaiterCancelsRequestWithoutLocalFallback()
    async throws {
    let clock = ManualOnboardingRecommendationClock()
    let local = OnboardingRecommendationLocalStub()
    let server = HangingOnboardingRecommendationServerStub()
    let account = MutableOnboardingRecommendationAccount(memberID: 98)
    let coordinator = OnboardingRecommendationCoordinator(
      serverService: server,
      localService: local,
      signedInMemberProvider: account,
      geminiDataConsent: GeminiDataConsentStub(),
      clock: clock
    )
    let task = _Concurrency.Task {
      try await coordinator.suggest(from: suggestionInput)
    }
    try await waitUntil {
      server.callCount == 1
    }

    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation.")
    } catch is CancellationError {
      XCTAssertEqual(local.callCount, 0)
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }
  }

  func testIdenticalConcurrentRequestsShareOneFlightAndOneWaiterCancellation()
    async throws {
    let account = MutableOnboardingRecommendationAccount(memberID: 98)
    let local = OnboardingRecommendationLocalStub()
    let gate = OnboardingRecommendationServerGate()
    let server = GatedOnboardingRecommendationServer(gate: gate)
    let diagnostics = OnboardingRecommendationDiagnosticsSpy()
    let coordinator = OnboardingRecommendationCoordinator(
      serverService: server,
      localService: local,
      signedInMemberProvider: account,
      geminiDataConsent: GeminiDataConsentStub(),
      diagnostics: diagnostics
    )

    let cancelledWaiter = _Concurrency.Task {
      try await coordinator.suggest(from: suggestionInput)
    }
    await gate.waitUntilRequested()
    let survivingWaiter = _Concurrency.Task {
      try await coordinator.suggest(from: suggestionInput)
    }
    try await waitUntil {
      diagnostics.events.contains(.joinedInFlight)
    }

    XCTAssertEqual(server.callCount, 1)
    cancelledWaiter.cancel()
    await gate.finish(with: serverRoutine)

    let result = try await survivingWaiter.value
    XCTAssertEqual(result.source, .server)
    XCTAssertEqual(server.callCount, 1)
    XCTAssertEqual(local.callCount, 0)

    do {
      _ = try await cancelledWaiter.value
      XCTFail("Expected only the cancelled waiter to be cancelled.")
    } catch is CancellationError {
      // The shared server request remained alive for the surviving waiter.
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }
  }

  func testHTTP429MapsToRetryableServerUnavailableFailure() {
    XCTAssertEqual(
      RoutineSuggestionRemoteFailureMapper.map(
        APIError.server(statusCode: 429, code: nil, message: "busy")
      ),
      .serverUnavailable
    )
  }

  func testUnknownPrimaryGoalDoesNotSkipToSecondaryGoal()
    async throws {
    let account = MutableOnboardingRecommendationAccount(memberID: 98)
    let local = OnboardingRecommendationLocalStub()
    let server = OnboardingRecommendationServerStub(
      result: .success(serverRoutine)
    )
    let coordinator = OnboardingRecommendationCoordinator(
      serverService: server,
      localService: local,
      signedInMemberProvider: account,
      geminiDataConsent: GeminiDataConsentStub()
    )
    var input = suggestionInput
    input.goalTags = ["unknown", "health"]

    do {
      _ = try await coordinator.suggest(from: input)
      XCTFail("Expected the unsupported primary goal to be surfaced.")
    } catch let error as RoutineSuggestionRequestError {
      XCTAssertEqual(error, .unsupportedOnboardingGoal)
    } catch {
      XCTFail("Expected RoutineSuggestionRequestError, got \(error)")
    }

    XCTAssertEqual(local.callCount, 0)
    XCTAssertEqual(server.callCount, 0)
  }

  func testAccountChangeDiscardsDelayedServerRecommendation()
    async throws {
    let account = MutableOnboardingRecommendationAccount(memberID: 98)
    let local = OnboardingRecommendationLocalStub()
    let gate = OnboardingRecommendationServerGate()
    let coordinator = OnboardingRecommendationCoordinator(
      serverService: GatedOnboardingRecommendationServer(gate: gate),
      localService: local,
      signedInMemberProvider: account,
      geminiDataConsent: GeminiDataConsentStub()
    )
    let task = _Concurrency.Task {
      try await coordinator.suggest(from: suggestionInput)
    }

    await gate.waitUntilRequested()
    account.memberID = 99
    await gate.finish(with: serverRoutine)

    do {
      _ = try await task.value
      XCTFail("Expected the account-changed response to be discarded.")
    } catch let error as RoutineSuggestionRequestError {
      XCTAssertEqual(error, .accountChanged)
    } catch {
      XCTFail("Expected RoutineSuggestionRequestError, got \(error)")
    }
    XCTAssertEqual(local.callCount, 0)
  }

  func testOnboardingRoutesExperienceChoicesToRecommendationAndFreeformAI()
    async throws {
    let goalCoordinator = CountingOnboardingSuggestionCoordinator(
      routine: serverRoutine
    )
    let aiCoordinator = CountingOnboardingSuggestionCoordinator(
      routine: Routine(
        name: "AI 재구성",
        steps: [
          RoutineStep(
            type: .confirm,
            title: "AI 단계",
            order: 0,
            estimatedSeconds: 60
          )
        ]
      )
    )
    let goalsViewModel = OnboardingViewModel(
      draft: OnboardingDraft(selectedGoalTags: ["health"]),
      step: .goals,
      routineSuggestionService: OnboardingRecommendationLocalStub(),
      routineSuggestionCoordinator: aiCoordinator,
      onboardingRecommendationCoordinator: goalCoordinator
    )

    goalsViewModel.primaryButtonDidTap()
    try await waitUntil {
      goalsViewModel.step == .suggestedRoutine
    }

    XCTAssertEqual(goalCoordinator.callCount, 1)
    XCTAssertEqual(aiCoordinator.callCount, 0)
    XCTAssertEqual(
      goalsViewModel.draft.previewRoutine?.name,
      serverRoutine.name
    )

    let freeformViewModel = OnboardingViewModel(
      draft: OnboardingDraft(
        experience: .hasRoutine,
        selectedGoalTags: ["health"],
        freeformText: "물을 마시고 싶어요"
      ),
      step: .experience,
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      routineSuggestionCoordinator: aiCoordinator,
      onboardingRecommendationCoordinator: goalCoordinator
    )

    freeformViewModel.primaryButtonDidTap()
    XCTAssertEqual(freeformViewModel.step, .freeform)
    freeformViewModel.primaryButtonDidTap()
    try await waitUntil(timeout: .seconds(6)) {
      freeformViewModel.step == .review
    }

    XCTAssertEqual(goalCoordinator.callCount, 1)
    XCTAssertEqual(aiCoordinator.callCount, 1)
    XCTAssertEqual(
      freeformViewModel.draft.previewRoutine?.name,
      "AI 재구성"
    )
    XCTAssertTrue(freeformViewModel.showsRecommendedRoutineStepEditor)
    XCTAssertEqual(
      freeformViewModel.recommendedRoutineStepCandidates.count,
      6
    )
    XCTAssertTrue(
      freeformViewModel.recommendedRoutineStepCandidates.contains {
        $0.title == "AI 단계"
      }
    )

    let additionalCandidate = try XCTUnwrap(
      freeformViewModel.recommendedRoutineStepCandidates.first {
        !freeformViewModel.isRecommendedRoutineStepSelected($0)
      }
    )
    freeformViewModel.toggleRecommendedRoutineStep(additionalCandidate)
    XCTAssertEqual(freeformViewModel.validatedPreviewRoutine?.steps.count, 2)
  }

  func testRecommendedAdditionKeepsExistingAICoordinator()
    async throws {
    let goalCoordinator = CountingOnboardingSuggestionCoordinator(
      routine: serverRoutine
    )
    let aiCoordinator = CountingOnboardingSuggestionCoordinator(
      routine: Routine(
        name: "기존 AI 추천",
        steps: [
          RoutineStep(
            type: .confirm,
            title: "AI 단계",
            order: 0,
            estimatedSeconds: 60
          )
        ]
      )
    )
    let viewModel = OnboardingViewModel(
      flowMode: .recommendedAddition,
      draft: OnboardingDraft(selectedGoalTags: ["habit"]),
      step: .goals,
      routineSuggestionService: OnboardingRecommendationLocalStub(),
      routineSuggestionCoordinator: aiCoordinator,
      onboardingRecommendationCoordinator: goalCoordinator
    )

    viewModel.primaryButtonDidTap()
    try await waitUntil {
      viewModel.step == .suggestedRoutine
    }

    XCTAssertEqual(goalCoordinator.callCount, 0)
    XCTAssertEqual(aiCoordinator.callCount, 1)
    XCTAssertEqual(
      viewModel.draft.previewRoutine?.name,
      "기존 AI 추천"
    )
    XCTAssertEqual(viewModel.previewSummary, "")
    XCTAssertTrue(viewModel.showsRecommendedRoutineStepEditor)
  }

  private var suggestionInput: RoutineSuggestionInput {
    RoutineSuggestionInput(
      experience: .wantsRecommendation,
      goalTags: ["health", "mind"],
      selectedKeywords: ["물 마시기"],
      freeformText: "",
      wakeUpHour: 6,
      wakeUpMinute: 40,
      weekdays: [.tuesday, .thursday]
    )
  }

  private var invalidServerResponse: ServerRoutineSuggestionResponse {
    ServerRoutineSuggestionResponse(
      title: " ",
      description: nil,
      steps: []
    )
  }

  private var validServerResponse: ServerRoutineSuggestionResponse {
    ServerRoutineSuggestionResponse(
      title: "서버 건강 루틴",
      description: "서버 추천 설명",
      steps: [
        ServerRoutineSuggestionStep(
          title: "물 마시기",
          kind: .check,
          durationSeconds: 60
        ),
        ServerRoutineSuggestionStep(
          title: "스트레칭",
          kind: .timer,
          durationSeconds: 180
        ),
        ServerRoutineSuggestionStep(
          title: "오늘의 다짐",
          kind: .input,
          durationSeconds: 90
        ),
      ]
    )
  }

  private var serverRoutine: Routine {
    Routine(
      name: "서버 추천",
      steps: [
        RoutineStep(
          type: .confirm,
          title: "서버 단계",
          order: 0,
          estimatedSeconds: 60
        )
      ]
    )
  }

  nonisolated private var recommendationResponseData: Data {
    Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": [
          {},
          {
            "routineGroupId": 10,
            "title": "서버 마음 루틴",
            "description": "서버 설명",
            "alarmDays": "MON,TUE",
            "alarmTime": "09:00",
            "weatherNotificationEnabled": true,
            "routines": [
              {
                "routineId": 101,
                "title": "물 마시기",
                "type": "CHECK",
                "durationSecond": 60,
                "steps": [
                  {
                    "stepId": 1001,
                    "content": "서버 내부 단계",
                    "orderIndex": 0
                  }
                ]
              },
              {
                "routineId": 102,
                "title": "스트레칭",
                "type": "TIMER",
                "durationSecond": 180
              },
              {
                "routineId": 103,
                "title": "오늘의 다짐",
                "type": "INPUT",
                "durationSecond": 90
              }
            ]
          }
        ]
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
      tokenProvider: OnboardingRecommendationAccessTokenProvider(),
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

  private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while !condition() {
      guard clock.now < deadline else {
        return XCTFail("Timed out waiting for onboarding recommendation.")
      }

      try await _Concurrency.Task<Never, Never>.sleep(
        for: .milliseconds(10)
      )
    }
  }
}

nonisolated private final class OnboardingRecommendationRemoteStub:
  ServerOnboardingRecommendationFetching,
  @unchecked Sendable {
  private let result:
    Result<[ServerRoutineSuggestionResponse], Error>

  init(
    result: Result<[ServerRoutineSuggestionResponse], Error>
  ) {
    self.result = result
  }

  func fetchRecommendations(
    for goal: OnboardingRecommendationGoal,
    memberID: Int64
  ) async throws -> [ServerRoutineSuggestionResponse] {
    try result.get()
  }
}

@MainActor
private final class OnboardingRecommendationServerStub:
  ServerOnboardingRecommendationServing {
  private let result: Result<Routine, Error>
  private(set) var callCount = 0

  init(result: Result<Routine, Error>) {
    self.result = result
  }

  func makeRoutine(
    from input: RoutineSuggestionInput,
    goal: OnboardingRecommendationGoal,
    memberID: Int64
  ) async throws -> Routine {
    callCount += 1
    return try result.get()
  }
}

@MainActor
private final class SequencedOnboardingRecommendationServerStub:
  ServerOnboardingRecommendationServing {
  private var results: [Result<Routine, Error>]
  private(set) var callCount = 0
  private(set) var maximumConcurrentCallCount = 0
  private var concurrentCallCount = 0

  init(results: [Result<Routine, Error>]) {
    self.results = results
  }

  func makeRoutine(
    from input: RoutineSuggestionInput,
    goal: OnboardingRecommendationGoal,
    memberID: Int64
  ) async throws -> Routine {
    callCount += 1
    concurrentCallCount += 1
    maximumConcurrentCallCount = max(
      maximumConcurrentCallCount,
      concurrentCallCount
    )
    defer {
      concurrentCallCount -= 1
    }

    guard !results.isEmpty else {
      throw RoutineSuggestionRemoteFailure.unavailable
    }
    return try results.removeFirst().get()
  }
}

@MainActor
private final class HangingOnboardingRecommendationServerStub:
  ServerOnboardingRecommendationServing {
  private(set) var callCount = 0

  func makeRoutine(
    from input: RoutineSuggestionInput,
    goal: OnboardingRecommendationGoal,
    memberID: Int64
  ) async throws -> Routine {
    callCount += 1
    try await _Concurrency.Task<Never, Never>.sleep(for: .seconds(3_600))
    throw RoutineSuggestionRemoteFailure.unavailable
  }
}

@MainActor
private final class OnboardingRecommendationLocalStub:
  RoutineSuggestionService {
  private(set) var callCount = 0

  func makeRoutine(
    from input: RoutineSuggestionInput
  ) throws -> Routine {
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
private final class MutableOnboardingRecommendationAccount:
  SignedInMemberProviding {
  var memberID: Int64?

  init(memberID: Int64?) {
    self.memberID = memberID
  }

  var signedInMemberID: Int64? {
    memberID
  }
}

@MainActor
private final class CountingOnboardingSuggestionCoordinator:
  RoutineSuggestionCoordinating {
  private let routine: Routine
  private(set) var callCount = 0

  init(routine: Routine) {
    self.routine = routine
  }

  func suggest(
    from input: RoutineSuggestionInput
  ) async throws -> RoutineSuggestionResult {
    callCount += 1
    return RoutineSuggestionResult(routine: routine, source: .server)
  }
}

private actor OnboardingRecommendationServerGate {
  private var requested = false
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []
  private var routine: Routine?
  private var resultWaiters: [CheckedContinuation<Routine, Never>] = []

  func waitForResult() async -> Routine {
    requested = true
    requestWaiters.forEach { $0.resume() }
    requestWaiters.removeAll()

    if let routine {
      return routine
    }

    return await withCheckedContinuation { continuation in
      resultWaiters.append(continuation)
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
    if !resultWaiters.isEmpty {
      let waiters = resultWaiters
      resultWaiters.removeAll()
      waiters.forEach { $0.resume(returning: routine) }
    } else {
      self.routine = routine
    }
  }
}

@MainActor
private final class GatedOnboardingRecommendationServer:
  ServerOnboardingRecommendationServing {
  private let gate: OnboardingRecommendationServerGate
  private(set) var callCount = 0
  private(set) var completionCount = 0

  init(gate: OnboardingRecommendationServerGate) {
    self.gate = gate
  }

  func makeRoutine(
    from input: RoutineSuggestionInput,
    goal: OnboardingRecommendationGoal,
    memberID: Int64
  ) async throws -> Routine {
    callCount += 1
    let routine = await gate.waitForResult()
    completionCount += 1
    return routine
  }
}

nonisolated private final class OnboardingRecommendationDiagnosticsSpy:
  OnboardingRecommendationDiagnosticReporting,
  @unchecked Sendable {
  private let lock = NSLock()
  private var recordedEvents: [OnboardingRecommendationDiagnosticEvent] = []

  var events: [OnboardingRecommendationDiagnosticEvent] {
    lock.withLock {
      recordedEvents
    }
  }

  func record(_ event: OnboardingRecommendationDiagnosticEvent) {
    lock.withLock {
      recordedEvents.append(event)
    }
  }
}

nonisolated private final class ManualOnboardingRecommendationClock:
  OnboardingRecommendationClock,
  @unchecked Sendable {
  private struct ScheduledSleep {
    let deadline: Duration
    let waiter: ManualOnboardingRecommendationSleepWaiter
  }

  private let lock = NSLock()
  private var currentTime: Duration = .zero
  private var sleeps: [UUID: ScheduledSleep] = [:]

  func now() -> Duration {
    lock.withLock {
      currentTime
    }
  }

  var pendingDeadlines: [Duration] {
    lock.withLock {
      sleeps.values.compactMap { sleep in
        sleep.waiter.isPending ? sleep.deadline : nil
      }
    }
  }

  func sleep(until deadline: Duration) async throws {
    let id = UUID()
    let waiter = ManualOnboardingRecommendationSleepWaiter()
    let shouldCompleteImmediately = lock.withLock {
      guard deadline > currentTime else {
        return true
      }
      sleeps[id] = ScheduledSleep(deadline: deadline, waiter: waiter)
      return false
    }

    if shouldCompleteImmediately {
      waiter.succeed()
    }

    try await waiter.wait()
  }

  func advance(by duration: Duration) {
    let dueWaiters: [ManualOnboardingRecommendationSleepWaiter] = lock.withLock {
      currentTime += duration
      let dueIDs = sleeps.compactMap { id, sleep in
        sleep.deadline <= currentTime ? id : nil
      }
      let waiters = dueIDs.compactMap { sleeps.removeValue(forKey: $0)?.waiter }
      return waiters
    }

    dueWaiters.forEach { $0.succeed() }
  }
}

nonisolated private final class ManualOnboardingRecommendationSleepWaiter:
  @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Error>?
  private var completion: Result<Void, Error>?

  var isPending: Bool {
    lock.withLock {
      completion == nil
    }
  }

  func wait() async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let completion = lock.withLock { () -> Result<Void, Error>? in
          if let completion = self.completion {
            return completion
          }
          self.continuation = continuation
          return nil
        }
        if let completion {
          Self.resume(continuation, with: completion)
        }
      }
    } onCancel: {
      finish(with: .failure(CancellationError()))
    }
  }

  func succeed() {
    finish(with: .success(()))
  }

  private func finish(with result: Result<Void, Error>) {
    let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
      guard completion == nil else {
        return nil
      }
      completion = result
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }

    if let continuation {
      Self.resume(continuation, with: result)
    }
  }

  private static func resume(
    _ continuation: CheckedContinuation<Void, Error>,
    with result: Result<Void, Error>
  ) {
    switch result {
    case .success:
      continuation.resume()
    case .failure(let error):
      continuation.resume(throwing: error)
    }
  }
}

nonisolated private final class OnboardingRecommendationAccessTokenProvider:
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

nonisolated private final class OnboardingRecommendationRequestCapturePlugin:
  PluginType,
  @unchecked Sendable {
  private let lock = NSLock()
  private var capturedRequest: URLRequest?

  var request: URLRequest? {
    lock.lock()
    defer { lock.unlock() }
    return capturedRequest
  }

  func prepare(
    _ request: URLRequest,
    target: TargetType
  ) -> URLRequest {
    lock.lock()
    capturedRequest = request
    lock.unlock()
    return request
  }
}
