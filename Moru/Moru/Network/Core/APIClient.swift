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

actor DefaultAPIClient: APIClient {
  private let provider: MoyaProvider<MultiTarget>
  private let configuration: NetworkConfiguration
  private let tokenProvider: any AccessTokenProviding
  private let decoder: JSONDecoder

  init(
    configuration: NetworkConfiguration = .production,
    tokenProvider: any AccessTokenProviding = EmptyAccessTokenProvider(),
    decoder: sending JSONDecoder = JSONDecoder(),
    providerFactory: MoyaProviderFactory = MoyaProviderFactory()
  ) {
    self.configuration = configuration
    self.tokenProvider = tokenProvider
    self.decoder = decoder
    self.provider = providerFactory.makeProvider(
      configuration: configuration
    )
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    let response = try await perform(target)
    try validateStatus(response)

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

  func requestVoid<Target: MoruTargetType>(_ target: Target) async throws {
    let response = try await perform(target)
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
    let response = try await perform(target)
    try validateStatus(response)
    return response.data
  }

  private func perform<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> HTTPResponseSnapshot {
    let accessToken = try accessToken(for: target)

    let cancellation = RequestCancellation()
    let adaptedTarget = MoyaTargetAdapter(
      target: target,
      baseURL: configuration.baseURL,
      requestAccessToken: accessToken
    )

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
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

      let nsError = error as NSError

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

nonisolated private final class RequestCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var request: Cancellable?
  private var isCancelled = false

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

    requestToCancel?.cancel()
  }
}
