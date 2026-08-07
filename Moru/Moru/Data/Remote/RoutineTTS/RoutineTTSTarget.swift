//
//  RoutineTTSTarget.swift
//  Moru
//

import Foundation

import Alamofire
import Moya

nonisolated enum RoutineTTSTarget: MoruTargetType {
  case manifest(routineGroupID: Int64)

  var path: String {
    switch self {
    case .manifest(let routineGroupID):
      "/routine-tts/\(routineGroupID)/tts"
    }
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
            "routineId": 31,
            "title": "물 마시기",
            "type": "CHECK",
            "steps": [
              {
                "stepId": 41,
                "content": "물 한 잔 준비하기",
                "ttsIntro": "물을 한 잔 준비해 볼까요?",
                "ttsStatus": "COMPLETED",
                "s3Url": "https://audio.example.com/41.mp3"
              }
            ]
          }
        ]
      }
      """.utf8
    )
  }
}
