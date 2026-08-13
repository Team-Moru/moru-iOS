//
//  RoutineExecutionAIStepTarget.swift
//  Moru
//

import Foundation

import Alamofire
import Moya

nonisolated enum RoutineExecutionAIStepTarget: MoruTargetType {
  case evaluate(RoutineExecutionAIStepRequestDTO)

  var path: String {
    "/routine-executions/ai-step"
  }

  var method: Moya.Method {
    .post
  }

  var task: Moya.Task {
    switch self {
    case .evaluate(let request):
      .requestJSONEncodable(request)
    }
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
          "aiResponse": "다음으로 넘어갈게요!",
          "shouldProceed": true
        }
      }
      """.utf8
    )
  }
}

nonisolated extension RoutineExecutionAIStepTarget:
  CustomStringConvertible,
  CustomDebugStringConvertible {
  var description: String {
    "RoutineExecutionAIStepTarget.evaluate(body: <redacted>)"
  }

  var debugDescription: String { description }
}
