//
//  APIClient.swift
//  Moru
//

import Foundation

import Alamofire
import Moya

nonisolated protocol APIClient: AnyObject, Sendable {
  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload

  func requestVoid<Target: MoruTargetType>(_ target: Target) async throws

  func requestData<Target: MoruTargetType>(_ target: Target) async throws -> Data
}

nonisolated protocol AccountBoundAPIClient: APIClient {
  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload

  func requestData<Target: MoruTargetType>(
    _ target: Target,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> Data

  /// Sends exactly one HTTP request for a non-idempotent operation. A 401 is
  /// returned to the caller without the normal token-refresh replay.
  func requestOnce<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> Payload
}

nonisolated protocol AccountBoundRawResponseClient: AccountBoundAPIClient {
  func requestResponse<Target: MoruTargetType>(
    _ target: Target,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> AccountBoundHTTPResponse
}

nonisolated struct AccountBoundHTTPResponse: Equatable, Sendable {
  let statusCode: Int
  let data: Data
}

nonisolated extension AccountBoundAPIClient {
  func requestData<Target: MoruTargetType>(
    _: Target,
    authorizedFor _: AccountSessionIdentity
  ) async throws -> Data {
    // Existing test/service clients cannot silently bypass the session gate.
    throw AccountAuthorizationContextError.memberMismatch
  }

  func requestOnce<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _: Target,
    as _: Payload.Type,
    authorizedFor _: AccountSessionIdentity
  ) async throws -> Payload {
    // Existing clients cannot silently downgrade an exact-session,
    // single-attempt request to member-only authorization.
    throw AccountAuthorizationContextError.memberMismatch
  }

  func requestOptional<
    Target: MoruTargetType,
    Payload: Decodable & Sendable
  >(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload? {
    do {
      return try await request(
        target,
        as: payloadType,
        authorizedForMemberID: memberID
      )
    } catch APIError.missingResult {
      return nil
    }
  }
}

actor DefaultAPIClient: AccountBoundRawResponseClient {
  private let provider: MoyaProvider<MultiTarget>
  private let configuration: NetworkConfiguration
  private let tokenProvider: any AccessTokenProviding
  private let accessTokenRefresher: (any AccessTokenRefreshing)?
  private let serverRequestsEnabled: Bool
  private let decoder: JSONDecoder
  private let requestCancellationFactory: @Sendable () -> RequestCancellation

  init(
    configuration: NetworkConfiguration = .production,
    tokenProvider: any AccessTokenProviding = EmptyAccessTokenProvider(),
    accessTokenRefresher: (any AccessTokenRefreshing)? = nil,
    serverRequestsEnabled: Bool = true,
    decoder: sending JSONDecoder = JSONDecoder(),
    providerFactory: MoyaProviderFactory = MoyaProviderFactory(),
    requestCancellationFactory: @escaping @Sendable () -> RequestCancellation = {
      RequestCancellation()
    }
  ) {
    self.configuration = configuration
    self.tokenProvider = tokenProvider
    self.accessTokenRefresher = accessTokenRefresher
    self.serverRequestsEnabled = serverRequestsEnabled
    self.decoder = decoder
    self.requestCancellationFactory = requestCancellationFactory
    self.provider = providerFactory.makeProvider(
      configuration: configuration
    )
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    try ensureServerRequestsEnabled()
    let response = try await perform(
      target,
      accessToken: try accessToken(for: target)
    )
    try validateStatus(response)

    return try successfulPayload(payloadType, from: response)
  }

  func requestResponse<Target: MoruTargetType>(
    _ target: Target,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> AccountBoundHTTPResponse {
    try ensureServerRequestsEnabled()
    let authorizationContext = try authorizationContext(
      for: target,
      identity: identity
    )
    let response: HTTPResponseSnapshot

    do {
      response = try await perform(
        target,
        accessToken: authorizationContext.accessToken,
        authorizationContext: authorizationContext
      )
    } catch {
      try validateAuthorizationContext(authorizationContext)
      throw error
    }

    try validateAuthorizationContext(authorizationContext)
    return AccountBoundHTTPResponse(
      statusCode: response.statusCode,
      data: response.data
    )
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> Data {
    try ensureServerRequestsEnabled()
    let authorizationContext = try authorizationContext(
      for: target,
      identity: identity
    )
    let response: HTTPResponseSnapshot

    do {
      response = try await perform(
        target,
        accessToken: authorizationContext.accessToken,
        authorizationContext: authorizationContext
      )
    } catch {
      try validateAuthorizationContext(authorizationContext)
      throw error
    }

    try validateAuthorizationContext(authorizationContext)
    try validateStatus(response)
    return response.data
  }

  func requestOnce<
    Target: MoruTargetType,
    Payload: Decodable & Sendable
  >(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> Payload {
    try ensureServerRequestsEnabled()
    let authorizationContext = try authorizationContext(
      for: target,
      identity: identity
    )

    do {
      // This path intentionally bypasses `perform`, whose 401 handling may
      // refresh credentials and replay a target. AI-step has no idempotency
      // contract, so every application submission must remain one HTTP call.
      let response = try await send(
        target,
        accessToken: authorizationContext.accessToken
      )
      try validateAuthorizationContext(authorizationContext)
      try validateStatus(response)
      let payload = try successfulPayload(payloadType, from: response)
      try validateAuthorizationContext(authorizationContext)
      return payload
    } catch {
      try _Concurrency.Task<Never, Never>.checkCancellation()
      try validateAuthorizationContext(authorizationContext)
      throw error
    }
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    try ensureServerRequestsEnabled()
    let authorizationContext = try authorizationContext(
      for: target,
      memberID: memberID
    )
    let response: HTTPResponseSnapshot

    do {
      response = try await perform(
        target,
        accessToken: authorizationContext.accessToken,
        authorizationContext: authorizationContext
      )
    } catch {
      try validateAuthorizationContext(authorizationContext)
      throw error
    }

    try validateAuthorizationContext(authorizationContext)
    try validateStatus(response)

    return try successfulPayload(payloadType, from: response)
  }

  func requestVoid<Target: MoruTargetType>(_ target: Target) async throws {
    try ensureServerRequestsEnabled()
    let response = try await perform(
      target,
      accessToken: try accessToken(for: target)
    )
    try validateStatus(response)

    guard response.statusCode != 204,
          response.statusCode != 205 else {
      return
    }

    _ = try decodeSuccessfulEnvelope(
      EmptyAPIResult.self,
      from: response
    )
  }

  func requestData<Target: MoruTargetType>(_ target: Target) async throws -> Data {
    try ensureServerRequestsEnabled()
    let response = try await perform(
      target,
      accessToken: try accessToken(for: target)
    )
    try validateStatus(response)
    return response.data
  }

  private func ensureServerRequestsEnabled() throws {
    guard serverRequestsEnabled else {
      throw APIError.capabilityDisabled
    }
  }

  private func perform<Target: MoruTargetType>(
    _ target: Target,
    accessToken: String?,
    authorizationContext: AccountAuthorizationContext? = nil
  ) async throws -> HTTPResponseSnapshot {
    let response = try await send(
      target,
      accessToken: accessToken
    )

    guard response.statusCode == 401,
          target.authenticationRequirement == .bearer,
          let failedAccessToken = accessToken,
          let accessTokenRefresher else {
      return response
    }

    let refreshResult: AccessTokenRefreshResult

    if let authorizationContext {
      try validateAuthorizationContext(authorizationContext)

      guard let accountBoundRefresher = accessTokenRefresher
        as? any AccountBoundAccessTokenRefreshing else {
        throw AccountAuthorizationContextError.memberMismatch
      }

      refreshResult = try await accountBoundRefresher.refreshAccessToken(
        afterUnauthorized: failedAccessToken,
        matching: authorizationContext
      )
      try validateAuthorizationContext(
        authorizationContext,
        accessToken: refreshResult.accessToken
      )
    } else {
      refreshResult = try await accessTokenRefresher.refreshAccessToken(
        afterUnauthorized: failedAccessToken
      )
    }
    let retryTarget: any MoruTargetType

    if let targetProvider = target
      as? any AuthenticationRetryTargetProviding {
      retryTarget = targetProvider.targetForAuthenticationRetry(
        using: refreshResult
      )
    } else {
      retryTarget = target
    }

    if let authorizationContext {
      try validateAuthorizationContext(
        authorizationContext,
        accessToken: refreshResult.accessToken
      )
    }

    return try await send(
      retryTarget,
      accessToken: refreshResult.accessToken
    )
  }

  private func successfulPayload<Payload: Decodable & Sendable>(
    _ payloadType: Payload.Type,
    from response: HTTPResponseSnapshot
  ) throws -> Payload {
    let envelope = try decodeSuccessfulEnvelope(
      payloadType,
      from: response
    )

    guard let result = envelope.result else {
      throw APIError.missingResult(
        code: envelope.code,
        message: envelope.message
      )
    }

    return result
  }

  private func send<Target: MoruTargetType>(
    _ target: Target,
    accessToken: String?
  ) async throws -> HTTPResponseSnapshot {
    let cancellation = requestCancellationFactory()
    let adaptedTarget = MoyaTargetAdapter(
      target: target,
      baseURL: configuration.baseURL,
      requestAccessToken: accessToken
    )

    return try await withTaskCancellationHandler {
      // Do not create a request when cancellation won the actor-hop race.
      // This is required for non-idempotent targets where even a promptly
      // cancelled POST may already have reached the server.
      guard !_Concurrency.Task<Never, Never>.isCancelled else {
        throw APIError.cancelled
      }
      return try await withCheckedThrowingContinuation { continuation in
        let request = provider.request(MultiTarget(adaptedTarget)) { result in
          switch result {
          case .success(let response):
            continuation.resume(
              returning: HTTPResponseSnapshot(
                statusCode: response.statusCode,
                data: response.data
              )
            )
          case .failure(let error):
            continuation.resume(throwing: Self.mapMoyaError(error))
          }
        }

        cancellation.store(request)
      }
    } onCancel: {
      cancellation.cancel()
    }
  }

  private func accessToken<Target: MoruTargetType>(
    for target: Target
  ) throws -> String? {
    guard target.authenticationRequirement == .bearer else {
      return nil
    }

    guard let token = tokenProvider.accessToken,
          !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw APIError.authenticationRequired
    }

    return token
  }

  private func authorizationContext<Target: MoruTargetType>(
    for target: Target,
    memberID: Int64
  ) throws -> AccountAuthorizationContext {
    guard target.authenticationRequirement == .bearer,
          memberID > 0,
          let accountTokenProvider = tokenProvider
            as? any AccountBoundAccessTokenProviding,
          let context = accountTokenProvider.authorizationContext(
            forMemberID: memberID
          ),
          !context.accessToken.trimmingCharacters(
            in: .whitespacesAndNewlines
          ).isEmpty else {
      throw AccountAuthorizationContextError.memberMismatch
    }

    return context
  }

  private func authorizationContext<Target: MoruTargetType>(
    for target: Target,
    identity: AccountSessionIdentity
  ) throws -> AccountAuthorizationContext {
    let context = try authorizationContext(
      for: target,
      memberID: identity.memberID
    )
    guard context.sessionID == identity.sessionID else {
      throw AccountAuthorizationContextError.memberMismatch
    }
    return context
  }

  private func validateAuthorizationContext(
    _ expected: AccountAuthorizationContext,
    accessToken: String? = nil
  ) throws {
    guard let accountTokenProvider = tokenProvider
      as? any AccountBoundAccessTokenProviding,
      let current = accountTokenProvider.authorizationContext(
        forMemberID: expected.memberID
      ),
      current.sessionID == expected.sessionID,
      accessToken == nil || current.accessToken == accessToken else {
      throw AccountAuthorizationContextError.memberMismatch
    }
  }

  private func validateStatus(_ response: HTTPResponseSnapshot) throws {
    guard (200..<300).contains(response.statusCode) else {
      let serverError = try? decoder.decode(
        ServerErrorResponse.self,
        from: response.data
      )

      throw APIError.server(
        statusCode: response.statusCode,
        code: serverError?.code,
        message: serverError?.message ?? HTTPURLResponse.localizedString(
          forStatusCode: response.statusCode
        )
      )
    }
  }

  private func decodeSuccessfulEnvelope<Payload: Decodable & Sendable>(
    _: Payload.Type,
    from response: HTTPResponseSnapshot
  ) throws -> APIResponse<Payload> {
    let envelope: APIResponse<Payload>

    do {
      envelope = try decoder.decode(
        APIResponse<Payload>.self,
        from: response.data
      )
    } catch {
      throw APIError.decoding(error.localizedDescription)
    }

    guard envelope.isSuccess else {
      throw APIError.server(
        statusCode: response.statusCode,
        code: envelope.code,
        message: envelope.message
      )
    }

    return envelope
  }

  static func mapMoyaError(_ error: MoyaError) -> APIError {
    switch error {
    case .requestMapping(let message):
      return .invalidRequest(message)
    case .encodableMapping(let error),
         .parameterEncoding(let error):
      return .invalidRequest(error.localizedDescription)
    case .underlying(let error, _):
      if error is CancellationError {
        return .cancelled
      }

      if let afError = error.asAFError,
         afError.isExplicitlyCancelledError {
        return .cancelled
      }

      // URLSession failures arrive through Moya wrapped in
      // AFError.sessionTaskFailed. Preserve the underlying URL error code so
      // callers can distinguish timeout and offline fallback behavior.
      let transportError = error.asAFError?.underlyingError ?? error

      if transportError is CancellationError {
        return .cancelled
      }

      let nsError = transportError as NSError

      if nsError.domain == NSURLErrorDomain,
         nsError.code == URLError.cancelled.rawValue {
        return .cancelled
      }

      return .transport(
        code: nsError.code,
        message: nsError.localizedDescription
      )
    default:
      return .transport(
        code: (error as NSError).code,
        message: error.localizedDescription
      )
    }
  }
}

nonisolated private struct HTTPResponseSnapshot: Sendable {
  let statusCode: Int
  let data: Data
}

/// Synchronizes task cancellation with Moya request creation. Internal so the
/// cancel-before-store race can be contract-tested without starting I/O.
nonisolated final class RequestCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private let onCancel: @Sendable () -> Void
  private var request: Cancellable?
  private var isCancelled = false

  init(onCancel: @escaping @Sendable () -> Void = {}) {
    self.onCancel = onCancel
  }

  func store(_ request: Cancellable) {
    lock.lock()

    if isCancelled {
      lock.unlock()
      request.cancel()
      return
    }

    self.request = request
    lock.unlock()
  }

  func cancel() {
    let requestToCancel: Cancellable?

    lock.lock()

    guard !isCancelled else {
      lock.unlock()
      return
    }

    isCancelled = true
    requestToCancel = request
    request = nil
    lock.unlock()

    onCancel()
    requestToCancel?.cancel()
  }
}
