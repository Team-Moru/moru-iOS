//
//  HistoryTarget.swift
//  Moru
//

import Foundation

import Alamofire
import Moya

nonisolated enum HistoryTarget: MoruTargetType {
  case weekly
  case monthly(year: Int, month: Int)
  case daily(date: String)
  case wakePattern

  var path: String {
    switch self {
    case .weekly:
      "/routine-executions/weekly"
    case .monthly:
      "/routine-executions/monthly"
    case .daily(let date):
      "/routine-executions/daily/\(date)"
    case .wakePattern:
      "/routine-executions/wake-pattern"
    }
  }

  var method: Moya.Method {
    .get
  }

  var task: Moya.Task {
    switch self {
    case .weekly:
      .requestPlain
    case .monthly(let year, let month):
      .requestParameters(
        parameters: [
          "year": year,
          "month": month,
        ],
        encoding: URLEncoding.queryString
      )
    case .daily, .wakePattern:
      .requestPlain
    }
  }

  var authenticationRequirement: AuthenticationRequirement {
    .bearer
  }

  var sampleData: Data {
    switch self {
    case .weekly:
      return Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "completionRate": 75,
            "completionRateDiff": -10,
            "totalDurationSecond": 3600,
            "weeklyCompletionRate": [
              {"day": "MON", "completionRate": 100},
              {"day": "TUE", "completionRate": 80},
              {"day": "WED", "completionRate": 60},
              {"day": "THU", "completionRate": 60},
              {"day": "FRI", "completionRate": null},
              {"day": "SAT", "completionRate": null},
              {"day": "SUN", "completionRate": null}
            ],
            "routineStats": [
              {"routineId": 1, "title": "물 마시기", "completionRate": 60}
            ]
          }
        }
        """.utf8
      )
    case .monthly(let year, let month):
      let monthText = String(format: "%02d", month)
      return Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": [
            {
              "executedDate": "\(year)-\(monthText)-01",
              "completionRate": 80
            }
          ]
        }
        """.utf8
      )
    case .daily(let date):
      return Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "executedDate": "\(date)",
            "completionRate": 60,
            "totalDurationSecond": 3600,
            "actualWakeTime": "07:23",
            "currentStreak": 7,
            "routines": [
              {
                "routineId": 1,
                "title": "물 마시기",
                "type": "CHECK",
                "durationSecond": 20,
                "isCompleted": true,
                "memberInput": "완료했어요"
              }
            ]
          }
        }
        """.utf8
      )
    case .wakePattern:
      return Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "avgWakeTime": "07:08",
            "wakeTimeDiffMin": -12,
            "regularityScore": 73,
            "stdDevMin": 18,
            "regularityLabel": "꽤 규칙적이에요"
          }
        }
        """.utf8
      )
    }
  }
}
