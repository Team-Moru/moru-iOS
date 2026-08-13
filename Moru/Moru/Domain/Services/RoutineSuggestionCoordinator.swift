//
//  RoutineSuggestionCoordinator.swift
//  Moru
//

import Foundation

enum RoutineSuggestionFallbackReason: Equatable {
  case signedOut
  case offline
  case timeout
  case serverUnavailable
  case invalidResponse
  case accountChanged
  case unavailable
}

enum RoutineSuggestionSource: Equatable {
  case server
  case localFallback(RoutineSuggestionFallbackReason)
}

struct RoutineSuggestionResult: Equatable {
  let routine: Routine
  let source: RoutineSuggestionSource
}

nonisolated protocol RoutineSuggestionInvalidDraftError: Error {}

nonisolated enum RoutineSuggestionFallbackPolicy {
  static func reason(
    for error: Error
  ) -> RoutineSuggestionFallbackReason {
    if error is any RoutineSuggestionInvalidDraftError {
      return .invalidResponse
    }

    guard let failure = error as? RoutineSuggestionRemoteFailure else {
      return .unavailable
    }

    switch failure {
    case .offline:
      return .offline
    case .timeout:
      return .timeout
    case .serverUnavailable:
      return .serverUnavailable
    case .invalidResponse:
      return .invalidResponse
    case .unavailable, .cancelled:
      return .unavailable
    }
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

  init(
    serverService: (any ServerRoutineSuggestionServing)?,
    localService: any RoutineSuggestionService,
    signedInMemberProvider: (any SignedInMemberProviding)?
  ) {
    self.serverService = serverService
    self.localService = localService
    self.signedInMemberProvider = signedInMemberProvider
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

    do {
      let routine = try await serverService.makeRoutine(
        from: input,
        memberID: memberID
      )

      guard signedInMemberProvider?.signedInMemberID == memberID else {
        return try localResult(from: input, reason: .accountChanged)
      }

      return RoutineSuggestionResult(routine: routine, source: .server)
    } catch is CancellationError {
      throw CancellationError()
    } catch RoutineSuggestionRemoteFailure.cancelled {
      throw CancellationError()
    } catch {
      guard signedInMemberProvider?.signedInMemberID == memberID else {
        return try localResult(from: input, reason: .accountChanged)
      }

      return try localResult(
        from: input,
        reason: RoutineSuggestionFallbackPolicy.reason(for: error)
      )
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

extension ServerRoutineSuggestionError: RoutineSuggestionInvalidDraftError {}
