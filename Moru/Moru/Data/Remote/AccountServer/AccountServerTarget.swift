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
                "proOnly": false,
                "previewAudioUrl": "https://moru-tts.s3.ap-northeast-2.amazonaws.com/previews/minseo.mp3",
                "doneAudioUrl": "https://moru-tts.s3.ap-northeast-2.amazonaws.com/common/minseo-done.mp3",
                "doneAudioStatus": "READY",
                "remindAudioUrl": "https://moru-tts.s3.ap-northeast-2.amazonaws.com/common/minseo-remind.mp3",
                "remindAudioStatus": "READY",
                "selectionVersion": 1
              },
              {
                "ttsId": 2,
                "voiceCode": "HYEONU",
                "displayName": "현우",
                "description": "차분한 친구",
                "proOnly": true,
                "previewAudioUrl": "https://moru-tts.s3.ap-northeast-2.amazonaws.com/previews/hyeonu.mp3",
                "doneAudioUrl": null,
                "doneAudioStatus": "PENDING",
                "remindAudioUrl": null,
                "remindAudioStatus": "PENDING",
                "selectionVersion": 1
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
            "displayName": "현우",
            "selectionVersion": 0
          }
        }
        """.utf8
      )
    }
  }
}
