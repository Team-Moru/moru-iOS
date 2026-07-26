//
//  VoiceTarget.swift
//  Moru
//

import Foundation

import Alamofire
import Moya

nonisolated enum VoiceTarget: MoruTargetType {
  case catalogue
  case updateSelection(TtsUpdateRequestDTO)

  var path: String {
    switch self {
    case .catalogue:
      "/tts"
    case .updateSelection:
      "/members/me/tts"
    }
  }

  var method: Moya.Method {
    switch self {
    case .catalogue:
      .get
    case .updateSelection:
      .patch
    }
  }

  var task: Moya.Task {
    switch self {
    case .catalogue:
      .requestPlain
    case .updateSelection(let request):
      .requestJSONEncodable(request)
    }
  }

  var authenticationRequirement: AuthenticationRequirement {
    .bearer
  }

  var sampleData: Data {
    switch self {
    case .catalogue:
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "voices": [
              {
                "ttsId": 1,
                "voiceCode": "MINSEO",
                "displayName": "민서",
                "description": "따뜻한 친구",
                "proOnly": false
              }
            ]
          }
        }
        """.utf8
      )
    case .updateSelection:
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "memberId": 1,
            "ttsId": 1,
            "voiceCode": "MINSEO",
            "displayName": "민서"
          }
        }
        """.utf8
      )
    }
  }
}
