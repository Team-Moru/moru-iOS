//
//  RoutineTTSTarget.swift
//  Moru
//

import Foundation

import Alamofire
import Moya

nonisolated enum RoutineTTSTarget:
  MoruTargetType,
  NetworkLogPathProviding {
  case list(routineGroupID: Int64)

  var path: String {
    switch self {
    case .list(let routineGroupID):
      "/routine-tts/\(routineGroupID)/tts"
    }
  }

  var networkLogPath: String {
    "/routine-tts/{routineGroupId}/tts"
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
        "result": [
          {
            "routineId": 14,
            "title": "스트레칭하기",
            "type": "TIMER",
            "steps": [
              {
                "stepId": 101,
                "content": "목 스트레칭",
                "ttsIntro": "이제 목을 부드럽게 풀어볼까요?",
                "ttsStatus": "COMPLETED",
                "s3Url": "https://moru-tts.s3.ap-northeast-2.amazonaws.com/101.mp3"
              }
            ]
          }
        ]
      }
      """.utf8
    )
  }
}
