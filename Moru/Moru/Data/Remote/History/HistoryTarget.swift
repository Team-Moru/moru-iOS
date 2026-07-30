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

  var path: String {
    switch self {
    case .weekly:
      "/routine-executions/weekly"
    case .monthly:
      "/routine-executions/monthly"
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
    }
  }
}
