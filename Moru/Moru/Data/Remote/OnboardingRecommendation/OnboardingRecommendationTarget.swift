//
//  OnboardingRecommendationTarget.swift
//  Moru
//

import Foundation

import Alamofire
import Moya

nonisolated enum OnboardingRecommendationGoalType:
  String,
  Equatable,
  Sendable {
  case vitality = "VITALITY"
  case health = "HEALTH"
  case stability = "STABILITY"
  case habit = "HABIT"

  init(goal: OnboardingRecommendationGoal) {
    switch goal {
    case .energy:
      self = .vitality
    case .health:
      self = .health
    case .mind:
      self = .stability
    case .habit:
      self = .habit
    }
  }
}

nonisolated enum OnboardingRecommendationTarget: MoruTargetType {
  case recommendations(goalType: OnboardingRecommendationGoalType)

  var path: String {
    "/onboarding/recommendations"
  }

  var method: Moya.Method {
    .get
  }

  var task: Moya.Task {
    switch self {
    case .recommendations(let goalType):
      .requestParameters(
        parameters: ["goalType": goalType.rawValue],
        encoding: URLEncoding.queryString
      )
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
        "result": [
          {
            "routineGroupId": 10,
            "title": "활력 루틴",
            "description": "몸을 깨우는 아침 루틴",
            "alarmDays": "MON,TUE,WED,THU,FRI",
            "alarmTime": "07:00",
            "weatherNotificationEnabled": true,
            "routines": [
              {
                "routineId": 101,
                "title": "물 한 잔 마시기",
                "type": "CHECK",
                "durationSecond": 60,
                "steps": []
              }
            ]
          }
        ]
      }
      """.utf8
    )
  }
}
