//
//  APIError.swift
//  Moru
//

import Foundation

nonisolated enum APIError: Error, Equatable, Sendable {
  case invalidRequest(String)
  case authenticationRequired
  case capabilityDisabled
  case transport(code: Int, message: String)
  case server(statusCode: Int, code: String?, message: String)
  case decoding(String)
  case missingResult(code: String, message: String)
  case cancelled
}

nonisolated extension APIError {
  var isRetryable: Bool {
    switch self {
    case .transport:
      true
    case .server(let statusCode, _, _):
      statusCode == 408 || statusCode == 429 || (500..<600).contains(statusCode)
    case .invalidRequest,
         .authenticationRequired,
         .capabilityDisabled,
         .decoding,
         .missingResult,
         .cancelled:
      false
    }
  }
}
