//
//  OnboardingRecommendationCoordinator.swift
//  Moru
//

import Foundation
import OSLog

nonisolated protocol OnboardingRecommendationClock: Sendable {
  func now() -> Duration
  func sleep(until deadline: Duration) async throws
}

nonisolated struct ContinuousOnboardingRecommendationClock:
  OnboardingRecommendationClock {
  private let clock = ContinuousClock()
  private let origin: ContinuousClock.Instant

  init() {
    origin = clock.now
  }

  func now() -> Duration {
    origin.duration(to: clock.now)
  }

  func sleep(until deadline: Duration) async throws {
    try await clock.sleep(until: origin.advanced(by: deadline))
  }
}

nonisolated struct OnboardingRecommendationRetryPolicy:
  Equatable,
  Sendable {
  let totalBudget: Duration
  let retryDelay: Duration
  let maximumRetryCount: Int

  static let production = OnboardingRecommendationRetryPolicy(
    totalBudget: .seconds(8),
    retryDelay: .milliseconds(500),
    maximumRetryCount: 1
  )
}

nonisolated private enum OnboardingRecommendationDeadlineError: Error {
  case exceeded
}

@MainActor
private final class OnboardingRecommendationRequestRace {
  private var completion: Result<Routine, Error>?
  private var continuation: CheckedContinuation<Routine, Error>?
  private var requestTask: Task<Void, Never>?
  private var deadlineTask: Task<Void, Never>?

  func install(_ continuation: CheckedContinuation<Routine, Error>) {
    guard let completion else {
      self.continuation = continuation
      return
    }

    continuation.resume(with: completion)
  }

  func register(
    requestTask: Task<Void, Never>,
    deadlineTask: Task<Void, Never>
  ) {
    guard completion == nil else {
      requestTask.cancel()
      deadlineTask.cancel()
      return
    }

    self.requestTask = requestTask
    self.deadlineTask = deadlineTask
  }

  @discardableResult
  func resolve(_ result: Result<Routine, Error>) -> Bool {
    guard completion == nil else {
      return false
    }

    completion = result
    let continuation = self.continuation
    self.continuation = nil
    let requestTask = self.requestTask
    self.requestTask = nil
    let deadlineTask = self.deadlineTask
    self.deadlineTask = nil

    requestTask?.cancel()
    deadlineTask?.cancel()
    continuation?.resume(with: result)
    return true
  }
}

nonisolated enum OnboardingRecommendationDiagnosticEvent:
  String,
  Equatable,
  Sendable {
  case requestStarted = "request_started"
  case retryScheduled = "retry_scheduled"
  case retryStarted = "retry_started"
  case serverSucceeded = "server_succeeded"
  case deadlineExceeded = "deadline_exceeded"
  case localFallback = "local_fallback"
  case joinedInFlight = "joined_in_flight"
}

nonisolated protocol OnboardingRecommendationDiagnosticReporting: Sendable {
  func record(_ event: OnboardingRecommendationDiagnosticEvent)
}

nonisolated struct OSLogOnboardingRecommendationDiagnostics:
  OnboardingRecommendationDiagnosticReporting {
  private static let logger = Logger(
    subsystem: "com.teammoru.Moru",
    category: "OnboardingRecommendation"
  )

  func record(_ event: OnboardingRecommendationDiagnosticEvent) {
    Self.logger.notice(
      "onboarding_recommendation_event=\(event.rawValue, privacy: .public)"
    )
  }
}

@MainActor
final class OnboardingRecommendationCoordinator:
  RoutineSuggestionCoordinating {
  private struct RequestKey: Hashable {
    let memberID: Int64
    let input: RoutineSuggestionInput
  }

  private struct InFlightRequest {
    let id: UUID
    let task: Task<RoutineSuggestionResult, Error>
    var waiterIDs: Set<UUID>
  }

  private struct DeadlineFallback {
    let requestID: UUID
    let result: RoutineSuggestionResult
  }

  private let serverService: (any ServerOnboardingRecommendationServing)?
  private let localService: any RoutineSuggestionService
  private weak var signedInMemberProvider: (any SignedInMemberProviding)?
  private let geminiDataConsent: any GeminiDataConsentAuthorizing
  private let clock: any OnboardingRecommendationClock
  private let retryPolicy: OnboardingRecommendationRetryPolicy
  private let diagnostics: any OnboardingRecommendationDiagnosticReporting
  private var inFlightRequests: [RequestKey: InFlightRequest] = [:]
  private var activeServerRequestIDs: Set<UUID> = []
  private var deadlineFallbacks: [RequestKey: DeadlineFallback] = [:]

  init(
    serverService: (any ServerOnboardingRecommendationServing)?,
    localService: any RoutineSuggestionService,
    signedInMemberProvider: (any SignedInMemberProviding)?,
    geminiDataConsent: any GeminiDataConsentAuthorizing,
    clock: any OnboardingRecommendationClock =
      ContinuousOnboardingRecommendationClock(),
    retryPolicy: OnboardingRecommendationRetryPolicy = .production,
    diagnostics: any OnboardingRecommendationDiagnosticReporting =
      OSLogOnboardingRecommendationDiagnostics()
  ) {
    self.serverService = serverService
    self.localService = localService
    self.signedInMemberProvider = signedInMemberProvider
    self.geminiDataConsent = geminiDataConsent
    self.clock = clock
    self.retryPolicy = retryPolicy
    self.diagnostics = diagnostics
  }

  func suggest(
    from input: RoutineSuggestionInput
  ) async throws -> RoutineSuggestionResult {
    guard let memberID = signedInMemberProvider?.signedInMemberID else {
      return try localResult(from: input, reason: .signedOut)
    }
    guard let primaryGoalTag = input.goalTags.first,
          let goal = OnboardingRecommendationGoal(
            rawValue: primaryGoalTag
          ) else {
      throw RoutineSuggestionRequestError.unsupportedOnboardingGoal
    }
    guard let serverService else {
      return try localResult(from: input, reason: .serverUnavailable)
    }

    switch try await RoutineSuggestionConsentPolicy.resolve(
      using: geminiDataConsent
    ) {
    case .useLocalFallbackAfterDecline:
      return try localResult(
        from: input,
        reason: .geminiConsentDeclined
      )
    case .useServer:
      break
    }

    try Task.checkCancellation()
    guard signedInMemberProvider?.signedInMemberID == memberID else {
      throw RoutineSuggestionRequestError.accountChanged
    }

    let key = RequestKey(memberID: memberID, input: input)
    if let deadlineFallback = deadlineFallbacks[key] {
      diagnostics.record(.joinedInFlight)
      return deadlineFallback.result
    }

    let waiterID = UUID()
    let request: InFlightRequest

    if var existingRequest = inFlightRequests[key] {
      existingRequest.waiterIDs.insert(waiterID)
      inFlightRequests[key] = existingRequest
      request = existingRequest
      diagnostics.record(.joinedInFlight)
    } else {
      let requestID = UUID()
      let task = Task { @MainActor [weak self] in
        guard let self else {
          throw CancellationError()
        }
        return try await self.performSuggestion(
          from: input,
          goal: goal,
          memberID: memberID,
          serverService: serverService,
          requestKey: key,
          requestID: requestID
        )
      }
      request = InFlightRequest(
        id: requestID,
        task: task,
        waiterIDs: [waiterID]
      )
      inFlightRequests[key] = request
    }

    defer {
      releaseWaiter(waiterID, for: key, requestID: request.id)
    }

    return try await withTaskCancellationHandler {
      let result = try await request.task.value
      try Task.checkCancellation()
      return result
    } onCancel: { [weak self] in
      Task { @MainActor in
        self?.releaseWaiter(waiterID, for: key, requestID: request.id)
      }
    }
  }

  private func performSuggestion(
    from input: RoutineSuggestionInput,
    goal: OnboardingRecommendationGoal,
    memberID: Int64,
    serverService: any ServerOnboardingRecommendationServing,
    requestKey: RequestKey,
    requestID: UUID
  ) async throws -> RoutineSuggestionResult {
    let deadline = clock.now() + retryPolicy.totalBudget

    do {
      let routine = try await makeServerRoutine(
        from: input,
        goal: goal,
        memberID: memberID,
        serverService: serverService,
        deadline: deadline,
        requestKey: requestKey,
        requestID: requestID
      )
      try Task.checkCancellation()

      guard signedInMemberProvider?.signedInMemberID == memberID else {
        throw RoutineSuggestionRequestError.accountChanged
      }

      diagnostics.record(.serverSucceeded)
      return RoutineSuggestionResult(routine: routine, source: .server)
    } catch is CancellationError {
      throw CancellationError()
    } catch RoutineSuggestionRemoteFailure.cancelled {
      throw CancellationError()
    } catch {
      try Task.checkCancellation()
      guard signedInMemberProvider?.signedInMemberID == memberID else {
        throw RoutineSuggestionRequestError.accountChanged
      }

      diagnostics.record(.localFallback)
      let result = try localResult(from: input, reason: .serverUnavailable)
      if error is OnboardingRecommendationDeadlineError,
         activeServerRequestIDs.contains(requestID) {
        deadlineFallbacks[requestKey] = DeadlineFallback(
          requestID: requestID,
          result: result
        )
      }
      return result
    }
  }

  private func makeServerRoutine(
    from input: RoutineSuggestionInput,
    goal: OnboardingRecommendationGoal,
    memberID: Int64,
    serverService: any ServerOnboardingRecommendationServing,
    deadline: Duration,
    requestKey: RequestKey,
    requestID: UUID
  ) async throws -> Routine {
    let race = OnboardingRecommendationRequestRace()
    activeServerRequestIDs.insert(requestID)

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        race.install(continuation)

        let requestTask = Task { @MainActor in
          defer {
            serverRequestDidFinish(
              for: requestKey,
              requestID: requestID
            )
          }

          do {
            let routine = try await performServerRequestLoop(
              from: input,
              goal: goal,
              memberID: memberID,
              serverService: serverService,
              deadline: deadline
            )
            race.resolve(.success(routine))
          } catch {
            race.resolve(.failure(error))
          }
        }

        let deadlineTask = Task { @MainActor [clock, diagnostics] in
          do {
            try await clock.sleep(until: deadline)
            if race.resolve(
              .failure(OnboardingRecommendationDeadlineError.exceeded)
            ) {
              diagnostics.record(.deadlineExceeded)
            }
          } catch {
            // The request completed or its caller was cancelled first.
          }
        }

        race.register(
          requestTask: requestTask,
          deadlineTask: deadlineTask
        )
      }
    } onCancel: {
      Task { @MainActor in
        race.resolve(.failure(CancellationError()))
      }
    }
  }

  private func performServerRequestLoop(
    from input: RoutineSuggestionInput,
    goal: OnboardingRecommendationGoal,
    memberID: Int64,
    serverService: any ServerOnboardingRecommendationServing,
    deadline: Duration
  ) async throws -> Routine {
    var retryCount = 0

    while true {
      try Task.checkCancellation()
      guard clock.now() < deadline else {
        throw OnboardingRecommendationDeadlineError.exceeded
      }
      guard signedInMemberProvider?.signedInMemberID == memberID else {
        throw RoutineSuggestionRequestError.accountChanged
      }

      diagnostics.record(
        retryCount == 0 ? .requestStarted : .retryStarted
      )

      do {
        let routine = try await serverService.makeRoutine(
          from: input,
          goal: goal,
          memberID: memberID
        )
        try Task.checkCancellation()
        return routine
      } catch is CancellationError {
        throw CancellationError()
      } catch RoutineSuggestionRemoteFailure.cancelled {
        throw CancellationError()
      } catch {
        try Task.checkCancellation()
        guard signedInMemberProvider?.signedInMemberID == memberID else {
          throw RoutineSuggestionRequestError.accountChanged
        }

        guard retryCount < retryPolicy.maximumRetryCount,
              Self.isTransient(error) else {
          throw error
        }

        retryCount += 1
        let retryAt = clock.now() + retryPolicy.retryDelay
        guard retryAt < deadline else {
          throw OnboardingRecommendationDeadlineError.exceeded
        }

        diagnostics.record(.retryScheduled)
        try await clock.sleep(until: retryAt)
      }
    }
  }

  private func releaseWaiter(
    _ waiterID: UUID,
    for key: RequestKey,
    requestID: UUID
  ) {
    guard var request = inFlightRequests[key],
          request.id == requestID,
          request.waiterIDs.remove(waiterID) != nil else {
      return
    }

    guard request.waiterIDs.isEmpty else {
      inFlightRequests[key] = request
      return
    }

    inFlightRequests.removeValue(forKey: key)
    request.task.cancel()
  }

  private func serverRequestDidFinish(
    for key: RequestKey,
    requestID: UUID
  ) {
    activeServerRequestIDs.remove(requestID)
    guard deadlineFallbacks[key]?.requestID == requestID else {
      return
    }
    deadlineFallbacks.removeValue(forKey: key)
  }

  private nonisolated static func isTransient(_ error: Error) -> Bool {
    guard let failure = error as? RoutineSuggestionRemoteFailure else {
      return false
    }

    switch failure {
    case .offline, .timeout, .serverUnavailable:
      return true
    case .invalidResponse, .unavailable, .cancelled:
      return false
    }
  }

  private func localResult(
    from input: RoutineSuggestionInput,
    reason: RoutineSuggestionFallbackReason
  ) throws -> RoutineSuggestionResult {
    RoutineSuggestionResult(
      routine: try localService.makeRoutine(from: input),
      source: .localFallback(reason)
    )
  }
}
