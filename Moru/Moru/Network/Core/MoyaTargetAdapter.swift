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
  Sendable {
  let target: Target
  let baseURL: URL
  let requestAccessToken: String?

  var path: String {
    target.path
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
