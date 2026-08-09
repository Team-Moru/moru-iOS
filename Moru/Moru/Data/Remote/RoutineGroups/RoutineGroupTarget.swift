//
//  RoutineGroupTarget.swift
//  Moru
//

import Foundation

import Alamofire
import Moya

nonisolated enum RoutineGroupTarget: MoruTargetType {
  case create(RoutineGroupCreateRequestDTO)
  case list
  case detail(routineGroupID: Int64)

  var path: String {
    switch self {
    case .create, .list:
      "/routine-groups"
    case .detail(let routineGroupID):
      "/routine-groups/\(routineGroupID)"
    }
  }

  var method: Moya.Method {
    switch self {
    case .create:
      .post
    case .list, .detail:
      .get
    }
  }

  var task: Moya.Task {
    switch self {
    case .create(let request):
      .requestJSONEncodable(request)
    case .list, .detail:
      .requestPlain
    }
  }

  var authenticationRequirement: AuthenticationRequirement {
    .bearer
  }

  var sampleData: Data {
    switch self {
    case .create:
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "routineGroupId": 12,
            "title": "아침 루틴",
            "description": "천천히 하루를 시작해요",
            "alarmDays": "MON,TUE,WED,THU,FRI",
            "alarmTime": "07:30",
            "weatherNotificationEnabled": true,
            "routines": [
              {
                "routineId": 31,
                "title": "물 마시기",
                "type": "CHECK",
                "durationSecond": 30,
                "steps": []
              }
            ]
          }
        }
        """.utf8
      )
    case .list:
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": [
            {
              "routineGroupId": 12,
              "title": "아침 루틴",
              "isActive": true,
              "routineCount": 2,
              "totalDurationSecond": 180
            }
          ]
        }
        """.utf8
      )
    case .detail(let routineGroupID):
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "routineGroupId": \(routineGroupID),
            "title": "아침 루틴",
            "description": "천천히 하루를 시작해요",
            "alarmDays": "MON,TUE,WED,THU,FRI",
            "alarmTime": "07:30",
            "weatherNotificationEnabled": true,
            "routines": [
              {
                "routineId": 31,
                "title": "물 마시기",
                "type": "CHECK",
                "durationSecond": 30,
                "steps": [
                  {
                    "stepId": 41,
                    "content": "물 한 잔 준비하기",
                    "orderIndex": 0
                  }
                ]
              }
            ]
          }
        }
        """.utf8
      )
    }
  }
}
