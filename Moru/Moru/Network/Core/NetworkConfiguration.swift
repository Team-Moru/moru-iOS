//
//  NetworkConfiguration.swift
//  Moru
//

import Foundation

nonisolated struct NetworkConfiguration: Equatable, Sendable {
  let baseURL: URL
  let requestTimeout: TimeInterval
  let resourceTimeout: TimeInterval

  init(
    baseURL: URL,
    requestTimeout: TimeInterval = 15,
    resourceTimeout: TimeInterval = 30
  ) {
    precondition(requestTimeout > 0, "requestTimeout must be greater than zero.")
    precondition(resourceTimeout >= requestTimeout, "resourceTimeout must cover requests.")

    self.baseURL = baseURL
    self.requestTimeout = requestTimeout
    self.resourceTimeout = resourceTimeout
  }

  static let production = NetworkConfiguration(
    baseURL: URL(string: "https://moru-api.duckdns.org")!,
    requestTimeout: 15,
    resourceTimeout: 30
  )
}
