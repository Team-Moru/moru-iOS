//
//  RoutineGroupTarget.swift
//  Moru
//

import Foundation

import Alamofire
import Moya

nonisolated enum RoutineGroupTarget: MoruTargetType {
  case list
  case detail(routineGroupID: Int64)
  case active
  case today
  case updateActivation(
    routineGroupID: Int64,
    request: RoutineGroupActivationRequestDTO
  )

  var path: String {
    switch self {
    case .list:
      "/routine-groups"
    case .detail(let routineGroupID):
      "/routine-groups/\(routineGroupID)"
    case .active:
      "/routine-groups/active"
    case .today:
      "/routine-groups/today"
    case .updateActivation(let routineGroupID, _):
      "/routine-groups/\(routineGroupID)/active"
    }
  }

  var method: Moya.Method {
    switch self {
    case .list, .detail, .active, .today:
      .get
    case .updateActivation:
      .patch
    }
  }

  var task: Moya.Task {
    switch self {
    case .list, .detail, .active, .today:
      .requestPlain
    case .updateActivation(_, let request):
      .requestJSONEncodable(request)
    }
  }

  var authenticationRequirement: AuthenticationRequirement {
    .bearer
  }

  var sampleData: Data {
    switch self {
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
    case .active:
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "routineGroupId": 12,
            "title": "아침 루틴",
            "totalDurationSec": 180,
            "completionRate": 50,
            "routines": [
              {
                "routineId": 31,
                "title": "물 마시기",
                "isCompleted": true,
                "completedTimeSec": 30
              }
            ]
          }
        }
        """.utf8
      )
    case .today:
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "completedCount": 1,
            "totalCount": 2,
            "completionRate": 50
          }
        }
        """.utf8
      )
    case .updateActivation(let routineGroupID, let request):
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "routineGroupId": \(routineGroupID),
            "isActive": \(request.isActive)
          }
        }
        """.utf8
      )
    }
  }
}
