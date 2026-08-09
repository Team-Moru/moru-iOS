//
//  RoutineExecutionTarget.swift
//  Moru
//

import Alamofire
import Foundation
import Moya

nonisolated enum RoutineExecutionTarget: MoruTargetType {
  case create(RoutineExecutionResultRequestDTO)
  case aiStep(RoutineExecutionAIRequestDTO)

  var path: String {
    switch self {
    case .create:
      "/routine-executions"
    case .aiStep:
      "/routine-executions/ai-step"
    }
  }

  var method: Moya.Method {
    .post
  }

  var task: Moya.Task {
    switch self {
    case .create(let request):
      .requestJSONEncodable(request)
    case .aiStep(let request):
      .requestJSONEncodable(request)
    }
  }

  var authenticationRequirement: AuthenticationRequirement {
    .bearer
  }

  var sampleData: Data {
    switch self {
    case .create(let request):
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "executedDate": "\(request.executedDate)",
            "executionId": 51,
            "routineId": \(request.routineId),
            "durationSecond": \(request.durationSecond ?? 0),
            "isCompleted": \(request.isCompleted)
          }
        }
        """.utf8
      )
    case .aiStep:
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
}
