//
//  RoutineSuggestionRemoteFailureMapper.swift
//  Moru
//

import Foundation

nonisolated protocol RoutineSuggestionInvalidResponseError:
  Error,
  Sendable {}

nonisolated enum RoutineSuggestionRemoteFailureMapper {
  static func map(_ error: Error) -> RoutineSuggestionRemoteFailure {
    if let failure = error as? RoutineSuggestionRemoteFailure {
      return failure
    }
    if error is any RoutineSuggestionInvalidResponseError {
      return .invalidResponse
    }
    if error is CancellationError {
      return .cancelled
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
    case .server(let statusCode, _, _) where statusCode == 408:
      return .timeout
    case .server(let statusCode, _, _)
      where statusCode == 429 || (500..<600).contains(statusCode):
      return .serverUnavailable
    case .decoding, .missingResult:
      return .invalidResponse
    case .cancelled:
      return .cancelled
    case .authenticationRequired,
         .capabilityDisabled,
         .invalidRequest,
         .server:
      return .unavailable
    }
  }
}
