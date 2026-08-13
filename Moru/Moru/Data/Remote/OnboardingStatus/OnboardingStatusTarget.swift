//
//  OnboardingStatusTarget.swift
//  Moru
//

import Foundation

import Alamofire
import Moya

nonisolated enum OnboardingStatusTarget: MoruTargetType {
  case status

  var path: String {
    "/onboarding/status"
  }

  var method: Moya.Method {
    .get
  }

  var task: Moya.Task {
    .requestPlain
  }

  var authenticationRequirement: AuthenticationRequirement {
    .bearer
  }

  var sampleData: Data {
    Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": {
          "onboardingCompleted": true
        }
      }
      """.utf8
    )
  }
}
