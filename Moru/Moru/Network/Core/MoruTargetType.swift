//
//  MoruTargetType.swift
//  Moru
//

import Foundation

import Moya

nonisolated protocol MoruTargetType: Sendable {
  var path: String { get }
  var method: Moya.Method { get }
  var task: Moya.Task { get }
  var sampleData: Data { get }
  var headers: [String: String]? { get }
  var authenticationRequirement: AuthenticationRequirement { get }
}

nonisolated extension MoruTargetType {
  var sampleData: Data {
    Data()
  }

  var headers: [String: String]? {
    ["Accept": "application/json"]
  }
}
