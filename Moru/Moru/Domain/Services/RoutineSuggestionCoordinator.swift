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

  var displayTitle: String {
    switch self {
    case .server:
      return "서버 맞춤 추천"
    case .localFallback:
      return "기기 내 추천"
    }
  }

  var displayMessage: String {
    switch self {
    case .server:
      return "서버가 만든 초안이에요. 저장 전 자유롭게 수정할 수 있어요."
    case .localFallback:
      return [
        "서버 연결 없이 만든 초안이에요.",
        "그대로 수정하고 저장할 수 있어요.",
      ].joined(separator: " ")
    }
  }
}

struct RoutineSuggestionResult: Equatable {
  let routine: Routine
  let source: RoutineSuggestionSource
}

@MainActor
protocol RoutineSuggestionAccountProviding: AnyObject {
  var routineSuggestionMemberID: Int64? { get }
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
  private weak var accountProvider: (any RoutineSuggestionAccountProviding)?

  init(
    serverService: (any ServerRoutineSuggestionServing)?,
    localService: any RoutineSuggestionService,
    accountProvider: (any RoutineSuggestionAccountProviding)?
  ) {
    self.serverService = serverService
    self.localService = localService
    self.accountProvider = accountProvider
  }

  func suggest(
    from input: RoutineSuggestionInput
  ) async throws -> RoutineSuggestionResult {
    guard let memberID = accountProvider?.routineSuggestionMemberID else {
      return try localResult(from: input, reason: .signedOut)
    }
    guard let serverService else {
      return try localResult(from: input, reason: .serverUnavailable)
    }

    do {
      let routine = try await serverService.makeRoutine(from: input)

      guard accountProvider?.routineSuggestionMemberID == memberID else {
        return try localResult(from: input, reason: .accountChanged)
      }

      return RoutineSuggestionResult(routine: routine, source: .server)
    } catch is CancellationError {
      throw CancellationError()
    } catch APIError.cancelled {
      throw CancellationError()
    } catch {
      guard accountProvider?.routineSuggestionMemberID == memberID else {
        return try localResult(from: input, reason: .accountChanged)
      }

      return try localResult(
        from: input,
        reason: Self.fallbackReason(for: error)
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

  private static func fallbackReason(
    for error: Error
  ) -> RoutineSuggestionFallbackReason {
    if error is ServerRoutineSuggestionError
      || error is RoutineSuggestionRemoteDataSourceError {
      return .invalidResponse
    }

    guard let apiError = error as? APIError else {
      return .unavailable
    }

    switch apiError {
    case .transport(let code, _):
      if code == URLError.timedOut.rawValue {
        return .timeout
      }
      if [
        URLError.notConnectedToInternet.rawValue,
        URLError.networkConnectionLost.rawValue,
        URLError.cannotConnectToHost.rawValue,
        URLError.cannotFindHost.rawValue,
      ].contains(code) {
        return .offline
      }
      return .unavailable
    case .server(let statusCode, _, _)
      where statusCode == 408:
      return .timeout
    case .server(let statusCode, _, _)
      where (500..<600).contains(statusCode):
      return .serverUnavailable
    case .decoding, .missingResult:
      return .invalidResponse
    case .authenticationRequired,
         .capabilityDisabled,
         .invalidRequest,
         .server,
         .cancelled:
      return .unavailable
    }
  }
}

extension AccountSessionStore: RoutineSuggestionAccountProviding {
  var routineSuggestionMemberID: Int64? {
    guard case .signedIn(let account) = state else {
      return nil
    }

    return account.memberID
  }
}
