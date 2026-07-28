//
//  APIError+ServerMutationFailureProviding.swift
//  Moru
//

extension APIError: ServerMutationFailureProviding {
  var serverMutationFailure: ServerMutationFailure {
    switch self {
    case .transport:
      .transport
    case .server(let statusCode, _, _) where statusCode == 408:
      .requestTimeout
    case .server(let statusCode, _, _) where statusCode == 429:
      .rateLimited
    case .server(let statusCode, _, _) where (500..<600).contains(statusCode):
      .serverUnavailable
    case .invalidRequest,
         .authenticationRequired,
         .capabilityDisabled,
         .server,
         .decoding,
         .missingResult,
         .cancelled:
      .nonRetryable
    }
  }
}
