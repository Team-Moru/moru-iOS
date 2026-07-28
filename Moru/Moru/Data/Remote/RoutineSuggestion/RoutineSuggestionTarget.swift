//
//  RoutineSuggestionTarget.swift
//  Moru
//

import Foundation

import Alamofire
import Moya

nonisolated enum RoutineSuggestionTarget: MoruTargetType {
  case generate(RoutineGroupAiGenerateRequestDTO)

  var path: String {
    "/routine-groups/ai-generate"
  }

  var method: Moya.Method {
    .post
  }

  var task: Moya.Task {
    switch self {
    case .generate(let request):
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
          "title": "활력 루틴",
          "description": "아침을 가볍게 시작하는 루틴",
          "routines": [
            {
              "title": "물 한 잔 마시기",
              "type": "CHECK",
              "durationSecond": 60
            },
            {
              "title": "가볍게 스트레칭하기",
              "type": "TIMER",
              "durationSecond": 180
            }
          ]
        }
      }
      """.utf8
    )
  }
}
