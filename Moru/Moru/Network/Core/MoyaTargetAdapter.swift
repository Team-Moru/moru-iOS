//
//  MoyaTargetAdapter.swift
//  Moru
//

import Foundation

import Moya

nonisolated struct MoyaTargetAdapter<Target: MoruTargetType>:
  TargetType,
  AccessTokenAuthorizable,
  RequestAccessTokenProviding,
  NetworkLogPathProviding,
  Sendable {
  let target: Target
  let baseURL: URL
  let requestAccessToken: String?

  var path: String {
    target.path
  }

  var networkLogPath: String {
    (target as? any NetworkLogPathProviding)?.networkLogPath ?? target.path
  }

  var method: Moya.Method {
    target.method
  }

  var task: Moya.Task {
    target.task
  }

  var sampleData: Data {
    target.sampleData
  }

  var headers: [String: String]? {
    target.headers?.filter {
      $0.key.caseInsensitiveCompare("Authorization") != .orderedSame
    }
  }

  var validationType: ValidationType {
    // HTTP status is interpreted centrally so server error bodies remain available.
    .none
  }

  var authorizationType: AuthorizationType? {
    switch target.authenticationRequirement {
    case .none:
      nil
    case .bearer:
      .bearer
    }
  }
}

nonisolated protocol RequestAccessTokenProviding: Sendable {
  var requestAccessToken: String? { get }
}

/// Lets targets containing server or account identifiers expose a stable,
/// redacted route template to the network logger.
nonisolated protocol NetworkLogPathProviding: Sendable {
  var networkLogPath: String { get }
}
