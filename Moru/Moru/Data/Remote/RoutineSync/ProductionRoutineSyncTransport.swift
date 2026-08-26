//
//  ProductionRoutineSyncTransport.swift
//  Moru
//

import Foundation
import OSLog

nonisolated enum RoutineSyncResponseDecodingError:
  Error,
  Equatable,
  Sendable {
  case processingConflict
  case idempotencyPayloadConflict
  case unknownConflict
  case definitiveServerRejection
  case invalidResponse
}

nonisolated protocol RoutineSyncTransportResponseDecoding: Sendable {
  func decodeCommit(
    for request: RoutineSyncTransportRequest,
    from responseData: Data
  ) throws -> RoutineSyncTransportCommit
}

nonisolated final class ProductionRoutineSyncTransport:
  RoutineSyncTransport,
  Sendable {
  private let apiClient: any AccountBoundAPIClient
  private let responseDecoder: any RoutineSyncTransportResponseDecoding
  /// The server's own error code/message for an unrecognized 409 carries no
  /// account or routine content, so it is safe to log verbatim.
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.teammoru.Moru",
    category: "RoutineSyncTransport"
  )

  init(
    apiClient: any AccountBoundAPIClient,
    responseDecoder: any RoutineSyncTransportResponseDecoding
  ) {
    self.apiClient = apiClient
    self.responseDecoder = responseDecoder
  }

  func execute(
    _ request: RoutineSyncTransportRequest
  ) async -> RoutineSyncTransportOutcome {
    guard request.serverNamespace == .production,
          let identity = request.sessionIdentity,
          identity.memberID == request.memberID else {
      return .blocked(.invalidStoredRequest)
    }
    let target = RoutineSyncWireTarget(
      wireRequest: request.wireRequest,
      idempotencyKey: request.idempotencyKey
    )

    let data: Data
    do {
      data = try await apiClient.requestData(
        target,
        authorizedFor: identity
      )
    } catch is AccountAuthorizationContextError {
      return .ambiguous
    } catch let error as APIError {
      return Self.outcome(for: error)
    } catch {
      return .ambiguous
    }

    do {
      return .committed(
        try responseDecoder.decodeCommit(for: request, from: data)
      )
    } catch let error as RoutineSyncResponseDecodingError {
      switch error {
      case .processingConflict:
        return .processingConflict
      case .idempotencyPayloadConflict:
        return .blocked(.idempotencyPayloadConflict)
      case .unknownConflict:
        return .blocked(.unknownConflict)
      case .definitiveServerRejection:
        return .blocked(.definitiveServerRejection)
      case .invalidResponse:
        // A write may have committed even though its response is malformed.
        return .ambiguous
      }
    } catch {
      return .ambiguous
    }
  }

  private static func outcome(for error: APIError) -> RoutineSyncTransportOutcome {
    switch error {
    case .server(let statusCode, let code, let message):
      if statusCode == 409, code == "COMMON409" {
        return .processingConflict
      }
      if statusCode == 409, code == "COMMON410" {
        return .blocked(.idempotencyPayloadConflict)
      }
      if statusCode == 409 {
        logger.notice(
          "Routine sync 409 unknownConflict: code=\(code ?? "nil", privacy: .public), message=\(message, privacy: .public)"
        )
        return .blocked(.unknownConflict)
      }
      if statusCode == 408 || statusCode == 429
        || (500..<600).contains(statusCode) {
        return .ambiguous
      }
      logger.notice(
        "Routine sync definitiveServerRejection: statusCode=\(statusCode), code=\(code ?? "nil", privacy: .public), message=\(message, privacy: .public)"
      )
      return .blocked(.definitiveServerRejection)

    case .transport, .cancelled, .decoding, .missingResult:
      return .ambiguous
    case .invalidRequest, .authenticationRequired, .capabilityDisabled:
      return .blocked(.invalidStoredRequest)
    }
  }
}
