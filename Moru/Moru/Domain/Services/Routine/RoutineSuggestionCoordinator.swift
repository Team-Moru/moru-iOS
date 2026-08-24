//
//  RoutineSuggestionCoordinator.swift
//  Moru
//

import Foundation
import OSLog

enum RoutineSuggestionFallbackReason: Equatable {
  case signedOut
  case serverUnavailable
  case geminiConsentDeclined

  var diagnosticLabel: String {
    switch self {
    case .signedOut:
      "signed_out"
    case .serverUnavailable:
      "server_unavailable"
    case .geminiConsentDeclined:
      "gemini_consent_declined"
    }
  }
}

enum RoutineSuggestionSource: Equatable {
  case server
  case localFallback(RoutineSuggestionFallbackReason)

  var diagnosticLabel: String {
    switch self {
    case .server:
      "server"
    case .localFallback(let reason):
      "local_\(reason.diagnosticLabel)"
    }
  }
}

struct RoutineSuggestionResult: Equatable {
  let routine: Routine
  let source: RoutineSuggestionSource
}

enum RoutineSuggestionRequestError: LocalizedError, Equatable {
  case accountChanged
  case geminiConsentDeferred
  case unsupportedOnboardingGoal

  var errorDescription: String? {
    switch self {
    case .accountChanged:
      "계정 정보가 변경되어 루틴 추천을 다시 시작해 주세요."
    case .geminiConsentDeferred:
      "AI 데이터 처리 동의 후 루틴 구조화를 다시 진행할 수 있어요."
    case .unsupportedOnboardingGoal:
      "선택한 목표로 루틴 추천을 만들 수 없어요."
    }
  }
}

@MainActor
enum RoutineSuggestionConsentResolution {
  case useServer
  case useLocalFallbackAfterDecline
}

@MainActor
enum RoutineSuggestionConsentPolicy {
  static func resolve(
    using authorizer: any GeminiDataConsentAuthorizing
  ) async throws -> RoutineSuggestionConsentResolution {
    while true {
      try Task.checkCancellation()

      switch authorizer.geminiDataConsentStatus {
      case .granted:
        return .useServer
      case .declined:
        return .useLocalFallbackAfterDecline
      case .undecided:
        authorizer.requestGeminiDataConsentIfNeeded()
        switch try await authorizer.waitForGeminiDataConsentDecision() {
        case .granted, .declined:
          continue
        case .deferred:
          throw RoutineSuggestionRequestError.geminiConsentDeferred
        }
      }
    }
  }
}

@MainActor
enum RoutineSuggestionDiagnostics {
  private static let logger = Logger(
    subsystem: "com.teammoru.Moru",
    category: "RoutineSuggestion"
  )

  static func record(_ source: RoutineSuggestionSource) {
    logger.notice(
      "routine_suggestion_source=\(source.diagnosticLabel, privacy: .public)"
    )
  }
}

@MainActor
protocol RoutineSuggestionCoordinating: AnyObject {
  func suggest(
    from input: RoutineSuggestionInput
  ) async throws -> RoutineSuggestionResult
}

@MainActor
final class RoutineSuggestionCoordinator: RoutineSuggestionCoordinating {
  private let serverService: (any ServerRoutineSuggestionServing)?
  private let localService: any RoutineSuggestionService
  private weak var signedInMemberProvider: (any SignedInMemberProviding)?
  private let geminiDataConsent: any GeminiDataConsentAuthorizing

  init(
    serverService: (any ServerRoutineSuggestionServing)?,
    localService: any RoutineSuggestionService,
    signedInMemberProvider: (any SignedInMemberProviding)?,
    geminiDataConsent: any GeminiDataConsentAuthorizing
  ) {
    self.serverService = serverService
    self.localService = localService
    self.signedInMemberProvider = signedInMemberProvider
    self.geminiDataConsent = geminiDataConsent
  }

  func suggest(
    from input: RoutineSuggestionInput
  ) async throws -> RoutineSuggestionResult {
    guard let memberID = signedInMemberProvider?.signedInMemberID else {
      return try localResult(from: input, reason: .signedOut)
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

    do {
      let routine = try await serverService.makeRoutine(
        from: input,
        memberID: memberID
      )
      try Task.checkCancellation()

      guard signedInMemberProvider?.signedInMemberID == memberID else {
        throw RoutineSuggestionRequestError.accountChanged
      }

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

      throw error
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
