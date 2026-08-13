//
//  AccountServerTarget.swift
//  Moru
//

import Foundation

import Alamofire
import Moya

nonisolated enum AccountServerTarget: MoruTargetType {
  case profile
  case streak
  case voices
  case updateTTS(TTSUpdateRequestDTO)

  var path: String {
    switch self {
    case .profile:
      "/members/me/profile"
    case .streak:
      "/members/me/streak"
    case .voices:
      "/tts"
    case .updateTTS:
      "/members/me/tts"
    }
  }

  var method: Moya.Method {
    switch self {
    case .updateTTS:
      .patch
    case .profile, .streak, .voices:
      .get
    }
  }

  var task: Moya.Task {
    switch self {
    case .updateTTS(let request):
      .requestJSONEncodable(request)
    case .profile, .streak, .voices:
      .requestPlain
    }
  }

  var authenticationRequirement: AuthenticationRequirement {
    .bearer
  }

  var sampleData: Data {
    switch self {
    case .profile:
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "memberId": 98,
            "nickname": "모루유저",
            "loginType": "KAKAO",
            "profileImageKey": null,
            "ttsId": 1
          }
        }
        """.utf8
      )
    case .streak:
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "currentStreak": 5,
            "maxStreak": 12,
            "weeklyStatus": [true, true, false, false, false, false, false]
          }
        }
        """.utf8
      )
    case .voices:
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
              },
              {
                "ttsId": 2,
                "voiceCode": "HYEONU",
                "displayName": "현우",
                "description": "차분한 친구",
                "proOnly": true
              }
            ]
          }
        }
        """.utf8
      )
    case .updateTTS(let request):
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "memberId": 98,
            "ttsId": \(request.ttsId),
            "voiceCode": "HYEONU",
            "displayName": "현우"
          }
        }
        """.utf8
      )
    }
  }
}
