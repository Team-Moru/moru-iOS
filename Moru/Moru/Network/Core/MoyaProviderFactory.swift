//
//  MoyaProviderFactory.swift
//  Moru
//

import Foundation

import Alamofire
import Moya

/// Immutable provider assembly recipe consumed by `DefaultAPIClient`.
nonisolated struct MoyaProviderFactory: Sendable {
  typealias Provider = MoyaProvider<MultiTarget>
  typealias EndpointBuilder = @Sendable (MultiTarget) -> Endpoint
  typealias StubBuilder = @Sendable (MultiTarget) -> StubBehavior

  private let endpointBuilder: EndpointBuilder
  private let stubBuilder: StubBuilder
  private let additionalPlugins: [any PluginType & Sendable]

  init(
    endpointBuilder: @escaping EndpointBuilder = {
      Provider.defaultEndpointMapping(for: $0)
    },
    stubBuilder: @escaping StubBuilder = { _ in .never },
    additionalPlugins: [any PluginType & Sendable] = []
  ) {
    self.endpointBuilder = endpointBuilder
    self.stubBuilder = stubBuilder
    self.additionalPlugins = additionalPlugins
  }

  func makeProvider(
    configuration: NetworkConfiguration
  ) -> Provider {
    let sessionConfiguration = makeSessionConfiguration(configuration: configuration)
    let session = Session(
      configuration: sessionConfiguration,
      startRequestsImmediately: false
    )
    let requestClosure = makeRequestClosure(
      timeoutInterval: configuration.requestTimeout
    )
    let accessTokenPlugin = AccessTokenPlugin { target in
      Self.accessTokenSnapshot(from: target) ?? ""
    }
    let plugins: [any PluginType] = [
      accessTokenPlugin,
      NetworkLogPlugin(),
    ] + additionalPlugins

    return Provider(
      endpointClosure: endpointBuilder,
      requestClosure: requestClosure,
      stubClosure: stubBuilder,
      session: session,
      plugins: plugins
    )
  }

  func makeSessionConfiguration(
    configuration: NetworkConfiguration
  ) -> URLSessionConfiguration {
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.headers = .default
    sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
    sessionConfiguration.timeoutIntervalForResource = configuration.resourceTimeout
    return sessionConfiguration
  }

  private static func accessTokenSnapshot(
    from target: TargetType
  ) -> String? {
    let adaptedTarget: TargetType

    if let multiTarget = target as? MultiTarget {
      adaptedTarget = multiTarget.target
    } else {
      adaptedTarget = target
    }

    return (adaptedTarget as? RequestAccessTokenProviding)?
      .requestAccessToken
  }

  private func makeRequestClosure(
    timeoutInterval: TimeInterval
  ) -> Provider.RequestClosure {
    { endpoint, completion in
      Provider.defaultRequestMapping(for: endpoint) { result in
        switch result {
        case .success(var request):
          request.timeoutInterval = timeoutInterval
          completion(.success(request))
        case .failure(let error):
          completion(.failure(error))
        }
      }
    }
  }
}
