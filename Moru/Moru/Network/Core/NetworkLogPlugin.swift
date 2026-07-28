//
//  NetworkLogPlugin.swift
//  Moru
//

import Foundation
import OSLog

import Alamofire
import Moya

nonisolated final class NetworkLogPlugin: PluginType, Sendable {
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.teammoru.Moru",
    category: "Network"
  )

  func willSend(_ request: RequestType, target: TargetType) {
    #if DEBUG
    logger.debug("\(Self.requestMessage(for: target), privacy: .public)")
    #endif
  }

  func didReceive(
    _ result: Result<Moya.Response, MoyaError>,
    target: TargetType
  ) {
    #if DEBUG
    switch result {
    case .success(let response):
      let message = Self.responseMessage(
        statusCode: response.statusCode,
        target: target
      )
      logger.debug("\(message, privacy: .public)")
    case .failure:
      logger.error("\(Self.failureMessage(for: target), privacy: .public)")
    }
    #endif
  }

  static func requestMessage(for target: TargetType) -> String {
    "➡️ \(target.method.rawValue) \(target.path)"
  }

  static func responseMessage(
    statusCode: Int,
    target: TargetType
  ) -> String {
    "⬅️ \(statusCode) \(target.path)"
  }

  static func failureMessage(for target: TargetType) -> String {
    "❌ request failed \(target.path)"
  }
}
