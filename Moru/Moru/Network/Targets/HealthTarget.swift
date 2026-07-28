//
//  HealthTarget.swift
//  Moru
//

import Foundation

import Alamofire
import Moya

nonisolated enum HealthTarget: MoruTargetType {
  case status

  var path: String {
    "/health"
  }

  var method: Moya.Method {
    .get
  }

  var task: Task {
    .requestPlain
  }

  var authenticationRequirement: AuthenticationRequirement {
    .none
  }

  var sampleData: Data {
    Data("OK".utf8)
  }
}
