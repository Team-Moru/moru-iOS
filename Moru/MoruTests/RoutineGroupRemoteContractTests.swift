//
//  RoutineGroupRemoteContractTests.swift
//  MoruTests
//

import Foundation
import XCTest

import Moya

@testable import Moru

nonisolated private var routineGroupIdentity: AccountSessionIdentity {
  AccountSessionIdentity(
    memberID: 98,
    sessionID: UUID(
      uuidString: "00000000-0000-0000-0000-000000000098"
    )!
  )
}

@MainActor
final class RoutineGroupRemoteContractTests: XCTestCase {
  func testTargetsMatchSwaggerAndSamplesDecode() throws {
    let list = RoutineGroupTarget.list
    let detail = RoutineGroupTarget.detail(routineGroupID: 12)
    let active = RoutineGroupTarget.active
    let today = RoutineGroupTarget.today

    XCTAssertEqual(list.path, "/routine-groups")
    XCTAssertEqual(detail.path, "/routine-groups/12")
    XCTAssertEqual(active.path, "/routine-groups/active")
    XCTAssertEqual(today.path, "/routine-groups/today")
    XCTAssertEqual(list.method, .get)
    XCTAssertEqual(detail.method, .get)
    XCTAssertEqual(active.method, .get)
    XCTAssertEqual(today.method, .get)
    XCTAssertEqual(list.authenticationRequirement, .bearer)
    XCTAssertEqual(detail.authenticationRequirement, .bearer)
    XCTAssertEqual(active.authenticationRequirement, .bearer)
    XCTAssertEqual(today.authenticationRequirement, .bearer)

    for target in [list, detail, active, today] {
      guard case .requestPlain = target.task else {
        return XCTFail("Expected a body-free GET request.")
      }
    }

    let decoder = JSONDecoder()
    let listEnvelope = try decoder.decode(
      APIResponse<[RoutineGroupSummaryResponseDTO]>.self,
      from: list.sampleData
    )
    let detailEnvelope = try decoder.decode(
      APIResponse<RoutineGroupDetailResponseDTO>.self,
      from: detail.sampleData
    )
    let activeEnvelope = try decoder.decode(
      APIResponse<ActiveRoutineGroupResponseDTO>.self,
      from: active.sampleData
    )
    let todayEnvelope = try decoder.decode(
      APIResponse<TodayRoutineGroupSummaryResponseDTO>.self,
      from: today.sampleData
    )

    XCTAssertEqual(listEnvelope.result?.first?.routineGroupId, 12)
    XCTAssertEqual(detailEnvelope.result?.routineGroupId, 12)
    XCTAssertEqual(
      detailEnvelope.result?.routines?.first?.steps?.first?.stepId,
      41
    )
    XCTAssertEqual(activeEnvelope.result?.routineGroupId, 12)
    XCTAssertEqual(activeEnvelope.result?.totalDurationSec, 180)
    XCTAssertEqual(activeEnvelope.result?.routines?.count, 2)
    XCTAssertEqual(todayEnvelope.result?.completedCount, 1)
    XCTAssertEqual(todayEnvelope.result?.completionRate, 50)
  }

  func testFetchesListAndDetailWithAccountBindingAndNoRequestBody()
    async throws {
    let capture = RoutineGroupRequestCapturePlugin()
    let service = makeStubbedService(additionalPlugins: [capture])

    let groups = try await service.fetchRoutineGroups(memberID: 98)
    let detail = try await service.fetchRoutineGroupDetail(
      routineGroupID: 12,
      memberID: 98
    )
    let active = try await service.fetchActiveRoutineGroup(
      identity: routineGroupIdentity
    )
    let today = try await service.fetchTodayRoutineGroupSummary(
      identity: routineGroupIdentity
    )

    XCTAssertEqual(
      groups,
      [
        ServerRoutineGroupSummary(
          routineGroupID: 12,
          title: "아침 루틴",
          isActive: true,
          routineCount: 2,
          totalDurationSeconds: 180
        ),
      ]
    )
    XCTAssertEqual(detail.routineGroupID, 12)
    XCTAssertEqual(detail.title, "아침 루틴")
    XCTAssertEqual(detail.alarmDaysRaw, "MON,TUE,WED,THU,FRI")
    XCTAssertEqual(detail.alarmTimeRaw, "07:30")
    XCTAssertEqual(detail.routines?.map(\.routineID), [31])
    XCTAssertEqual(detail.routines?.first?.steps?.map(\.stepID), [41])
    XCTAssertEqual(
      active,
      ServerActiveRoutineGroup(
        routineGroupID: 12,
        title: "아침 루틴",
        totalDurationSeconds: 180,
        completionRate: 0.5,
        routines: [
          ServerActiveRoutine(
            routineID: 31,
            title: "물 마시기",
            isCompleted: true,
            completedTimeSeconds: 30
          ),
          ServerActiveRoutine(
            routineID: 32,
            title: "스트레칭",
            isCompleted: false,
            completedTimeSeconds: nil
          ),
        ]
      )
    )
    XCTAssertEqual(
      today,
      ServerTodayRoutineGroupSummary(
        completedCount: 1,
        totalCount: 2,
        completionRate: 0.5
      )
    )

    XCTAssertEqual(
      capture.requests.compactMap(\.url?.path),
      [
        "/routine-groups",
        "/routine-groups/12",
        "/routine-groups/active",
        "/routine-groups/today",
      ]
    )
    XCTAssertTrue(
      capture.requests.allSatisfy {
        $0.httpMethod == "GET"
          && $0.httpBody == nil
          && $0.value(forHTTPHeaderField: "Authorization")
            == "Bearer access-token"
      }
    )
  }

  func testDTOsDecodeEverySwaggerFieldAsOptional() throws {
    let decoder = JSONDecoder()
    let summary = try decoder.decode(
      RoutineGroupSummaryResponseDTO.self,
      from: Data("{}".utf8)
    )
    let detail = try decoder.decode(
      RoutineGroupDetailResponseDTO.self,
      from: Data("{}".utf8)
    )
    let routine = try decoder.decode(
      RoutineGroupRoutineResponseDTO.self,
      from: Data("{}".utf8)
    )
    let step = try decoder.decode(
      RoutineGroupStepResponseDTO.self,
      from: Data("{}".utf8)
    )
    let active = try decoder.decode(
      ActiveRoutineGroupResponseDTO.self,
      from: Data("{}".utf8)
    )
    let activeRoutine = try decoder.decode(
      ActiveRoutineResponseDTO.self,
      from: Data("{}".utf8)
    )
    let today = try decoder.decode(
      TodayRoutineGroupSummaryResponseDTO.self,
      from: Data("{}".utf8)
    )

    XCTAssertNil(summary.routineGroupId)
    XCTAssertNil(summary.title)
    XCTAssertNil(summary.isActive)
    XCTAssertNil(summary.routineCount)
    XCTAssertNil(summary.totalDurationSecond)
    XCTAssertNil(detail.routineGroupId)
    XCTAssertNil(detail.routines)
    XCTAssertNil(routine.routineId)
    XCTAssertNil(routine.steps)
    XCTAssertNil(step.stepId)
    XCTAssertNil(step.orderIndex)
    XCTAssertNil(active.routineGroupId)
    XCTAssertNil(active.title)
    XCTAssertNil(active.totalDurationSec)
    XCTAssertNil(active.completionRate)
    XCTAssertNil(active.routines)
    XCTAssertNil(activeRoutine.routineId)
    XCTAssertNil(activeRoutine.title)
    XCTAssertNil(activeRoutine.isCompleted)
    XCTAssertNil(activeRoutine.completedTimeSec)
    XCTAssertNil(today.completedCount)
    XCTAssertNil(today.totalCount)
    XCTAssertNil(today.completionRate)
  }

  func testListPreservesServerOrderDuplicateTitlesAndUnknownValues()
    async throws {
    let service = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupPayloadAPIClient(
        summaries: [
          routineGroupSummaryDTO(
            routineGroupId: 9,
            title: " 같은 이름 ",
            isActive: nil,
            routineCount: nil,
            totalDurationSecond: nil
          ),
          routineGroupSummaryDTO(
            routineGroupId: 3,
            title: "같은 이름",
            isActive: false,
            routineCount: 0,
            totalDurationSecond: 0
          ),
        ]
      )
    )

    let groups = try await service.fetchRoutineGroups(memberID: 98)

    XCTAssertEqual(groups.map(\.routineGroupID), [9, 3])
    XCTAssertEqual(groups.map(\.title), ["같은 이름", "같은 이름"])
    XCTAssertNil(groups[0].isActive)
    XCTAssertNil(groups[0].routineCount)
    XCTAssertNil(groups[0].totalDurationSeconds)
    XCTAssertEqual(groups[1].routineCount, 0)
    XCTAssertEqual(groups[1].totalDurationSeconds, 0)
  }

  func testEmptyListIsAValidServerResult() async throws {
    let service = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupPayloadAPIClient(summaries: [])
    )

    let groups = try await service.fetchRoutineGroups(memberID: 98)

    XCTAssertEqual(groups, [])
  }

  func testInt32FieldsAcceptSwaggerMaximumValue() async throws {
    let maximum = Int(Int32.max)
    let service = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupPayloadAPIClient(
        summaries: [
          routineGroupSummaryDTO(
            routineCount: maximum,
            totalDurationSecond: maximum
          ),
        ],
        detail: routineGroupDetailDTO(
          routines: [
            routineDTO(
              durationSecond: maximum,
              steps: [stepDTO(orderIndex: maximum)]
            ),
          ]
        )
      )
    )

    let groups = try await service.fetchRoutineGroups(memberID: 98)
    let detail = try await service.fetchRoutineGroupDetail(
      routineGroupID: 12,
      memberID: 98
    )

    XCTAssertEqual(groups.first?.routineCount, maximum)
    XCTAssertEqual(groups.first?.totalDurationSeconds, maximum)
    XCTAssertEqual(detail.routines?.first?.durationSeconds, maximum)
    XCTAssertEqual(
      detail.routines?.first?.steps?.first?.orderIndex,
      maximum
    )
  }

  func testListRejectsMissingNonpositiveDuplicateIDsAndInvalidValues()
    async {
    let invalidLists: [[RoutineGroupSummaryResponseDTO]] = [
      [routineGroupSummaryDTO(routineGroupId: nil)],
      [routineGroupSummaryDTO(routineGroupId: 0)],
      [routineGroupSummaryDTO(routineGroupId: -1)],
      [
        routineGroupSummaryDTO(routineGroupId: 1),
        routineGroupSummaryDTO(routineGroupId: 1),
      ],
      [routineGroupSummaryDTO(title: " \n ")],
      [routineGroupSummaryDTO(routineCount: -1)],
      [routineGroupSummaryDTO(totalDurationSecond: -1)],
      [routineGroupSummaryDTO(routineCount: Int(Int32.max) + 1)],
      [
        routineGroupSummaryDTO(
          totalDurationSecond: Int(Int32.max) + 1
        ),
      ],
    ]

    for summaries in invalidLists {
      let service = DefaultAccountRoutineGroupRemoteService(
        apiClient: RoutineGroupPayloadAPIClient(summaries: summaries)
      )
      await assertRemoteError(.invalidResponse(reason: "")) {
        _ = try await service.fetchRoutineGroups(memberID: 98)
      }
    }
  }

  func testDetailPreservesOrderRawScheduleAndUnknownRoutineType()
    async throws {
    let detail = routineGroupDetailDTO(
      title: "  아침 준비  ",
      description: "  하루 시작  ",
      alarmDays: " MON,FUTURE_DAY ",
      alarmTime: " 07:30 ",
      routines: [
        routineDTO(
          routineId: 8,
          title: " 둘째 ",
          type: "FUTURE_TYPE",
          durationSecond: nil,
          steps: [
            stepDTO(stepId: 2, content: " 나중 ", orderIndex: 7),
            stepDTO(stepId: 1, content: nil, orderIndex: nil),
          ]
        ),
        routineDTO(
          routineId: 4,
          title: nil,
          type: nil,
          durationSecond: 0,
          steps: [
            stepDTO(stepId: 2, content: " 다른 루틴 ", orderIndex: 0),
          ]
        ),
      ]
    )
    let service = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupPayloadAPIClient(detail: detail)
    )

    let mapped = try await service.fetchRoutineGroupDetail(
      routineGroupID: 12,
      memberID: 98
    )

    XCTAssertEqual(mapped.title, "아침 준비")
    XCTAssertEqual(mapped.description, "하루 시작")
    XCTAssertEqual(mapped.alarmDaysRaw, "MON,FUTURE_DAY")
    XCTAssertEqual(mapped.alarmTimeRaw, "07:30")
    XCTAssertEqual(mapped.routines?.map(\.routineID), [8, 4])
    XCTAssertEqual(mapped.routines?.first?.type, .unknown("FUTURE_TYPE"))
    XCTAssertNil(mapped.routines?.last?.type)
    XCTAssertEqual(
      mapped.routines?.first?.steps?.map(\.stepID),
      [2, 1]
    )
    XCTAssertEqual(mapped.routines?.first?.steps?.first?.content, "나중")
    XCTAssertEqual(mapped.routines?.first?.steps?.first?.orderIndex, 7)
    XCTAssertEqual(mapped.routines?.last?.steps?.first?.stepID, 2)
  }

  func testKnownRoutineTypesMapWithoutChangingMeaning() async throws {
    let service = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupPayloadAPIClient(
        detail: routineGroupDetailDTO(
          routines: [
            routineDTO(routineId: 1, type: "CHECK"),
            routineDTO(routineId: 2, type: "TIMER"),
            routineDTO(routineId: 3, type: "INPUT"),
          ]
        )
      )
    )

    let detail = try await service.fetchRoutineGroupDetail(
      routineGroupID: 12,
      memberID: 98
    )

    XCTAssertEqual(
      detail.routines?.map(\.type),
      [.check, .timer, .input]
    )
  }

  func testDetailKeepsOmittedArraysDifferentFromEmptyArrays()
    async throws {
    let omittedService = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupPayloadAPIClient(
        detail: routineGroupDetailDTO(routines: nil)
      )
    )
    let omitted = try await omittedService.fetchRoutineGroupDetail(
      routineGroupID: 12,
      memberID: 98
    )

    let emptyService = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupPayloadAPIClient(
        detail: routineGroupDetailDTO(
          routines: [
            routineDTO(routineId: 1, steps: nil),
            routineDTO(routineId: 2, steps: []),
          ]
        )
      )
    )
    let empty = try await emptyService.fetchRoutineGroupDetail(
      routineGroupID: 12,
      memberID: 98
    )

    XCTAssertNil(omitted.routines)
    XCTAssertNil(empty.routines?.first?.steps)
    XCTAssertEqual(empty.routines?.last?.steps, [])

    let noRoutinesService = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupPayloadAPIClient(
        detail: routineGroupDetailDTO(routines: [])
      )
    )
    let noRoutines = try await noRoutinesService.fetchRoutineGroupDetail(
      routineGroupID: 12,
      memberID: 98
    )
    XCTAssertEqual(noRoutines.routines, [])
  }

  func testDetailAcceptsMissingNonIdentityFields() async throws {
    let service = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupPayloadAPIClient(
        detail: RoutineGroupDetailResponseDTO(
          routineGroupId: 12,
          title: nil,
          description: nil,
          alarmDays: nil,
          alarmTime: nil,
          weatherNotificationEnabled: nil,
          routines: nil
        )
      )
    )

    let detail = try await service.fetchRoutineGroupDetail(
      routineGroupID: 12,
      memberID: 98
    )

    XCTAssertEqual(detail.routineGroupID, 12)
    XCTAssertNil(detail.title)
    XCTAssertNil(detail.description)
    XCTAssertNil(detail.alarmDaysRaw)
    XCTAssertNil(detail.alarmTimeRaw)
    XCTAssertNil(detail.weatherNotificationEnabled)
    XCTAssertNil(detail.routines)
  }

  func testDetailRejectsMismatchedOrInvalidIdentities()
    async {
    let invalidDetails = [
      routineGroupDetailDTO(routineGroupId: nil),
      routineGroupDetailDTO(routineGroupId: 0),
      routineGroupDetailDTO(routineGroupId: 13),
      routineGroupDetailDTO(
        routines: [routineDTO(routineId: nil)]
      ),
      routineGroupDetailDTO(
        routines: [routineDTO(routineId: 0)]
      ),
      routineGroupDetailDTO(
        routines: [
          routineDTO(routineId: 1),
          routineDTO(routineId: 1),
        ]
      ),
      routineGroupDetailDTO(
        routines: [
          routineDTO(
            steps: [stepDTO(stepId: nil)]
          ),
        ]
      ),
      routineGroupDetailDTO(
        routines: [
          routineDTO(
            steps: [stepDTO(stepId: 0)]
          ),
        ]
      ),
      routineGroupDetailDTO(
        routines: [
          routineDTO(
            steps: [
              stepDTO(stepId: 1),
              stepDTO(stepId: 1),
            ]
          ),
        ]
      ),
    ]

    for detail in invalidDetails {
      let service = DefaultAccountRoutineGroupRemoteService(
        apiClient: RoutineGroupPayloadAPIClient(detail: detail)
      )
      await assertRemoteError(.invalidResponse(reason: "")) {
        _ = try await service.fetchRoutineGroupDetail(
          routineGroupID: 12,
          memberID: 98
        )
      }
    }
  }

  func testDetailRejectsPresentBlankTextAndNegativeOptionalNumbers()
    async {
    let invalidDetails = [
      routineGroupDetailDTO(title: " "),
      routineGroupDetailDTO(description: "\n"),
      routineGroupDetailDTO(alarmDays: " "),
      routineGroupDetailDTO(alarmTime: "\t"),
      routineGroupDetailDTO(
        routines: [routineDTO(title: " ")]
      ),
      routineGroupDetailDTO(
        routines: [routineDTO(type: "\n")]
      ),
      routineGroupDetailDTO(
        routines: [routineDTO(durationSecond: -1)]
      ),
      routineGroupDetailDTO(
        routines: [
          routineDTO(durationSecond: Int(Int32.max) + 1),
        ]
      ),
      routineGroupDetailDTO(
        routines: [
          routineDTO(steps: [stepDTO(content: " ")])
        ]
      ),
      routineGroupDetailDTO(
        routines: [
          routineDTO(steps: [stepDTO(orderIndex: -1)])
        ]
      ),
      routineGroupDetailDTO(
        routines: [
          routineDTO(
            steps: [
              stepDTO(orderIndex: Int(Int32.max) + 1),
            ]
          ),
        ]
      ),
    ]

    for detail in invalidDetails {
      let service = DefaultAccountRoutineGroupRemoteService(
        apiClient: RoutineGroupPayloadAPIClient(detail: detail)
      )
      await assertRemoteError(.invalidResponse(reason: "")) {
        _ = try await service.fetchRoutineGroupDetail(
          routineGroupID: 12,
          memberID: 98
        )
      }
    }
  }

  func testActiveMapsRequiredFieldsAndPercentageBoundaries()
    async throws {
    let maximum = Int(Int32.max)
    let service = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupPayloadAPIClient(
        active: activeRoutineGroupDTO(
          title: "  아침 루틴  ",
          totalDurationSec: maximum,
          completionRate: 100,
          routines: [
            activeRoutineDTO(
              title: "  물 마시기  ",
              isCompleted: true,
              completedTimeSec: maximum
            ),
            activeRoutineDTO(
              routineId: 32,
              title: "스트레칭",
              isCompleted: false,
              completedTimeSec: nil
            ),
          ]
        )
      )
    )

    let active = try await service.fetchActiveRoutineGroup(identity: routineGroupIdentity)

    XCTAssertEqual(active?.title, "아침 루틴")
    XCTAssertEqual(active?.totalDurationSeconds, maximum)
    XCTAssertEqual(active?.completionRate, 1)
    XCTAssertEqual(active?.routines.map(\.routineID), [31, 32])
    XCTAssertEqual(active?.routines.first?.title, "물 마시기")
    XCTAssertEqual(active?.routines.first?.completedTimeSeconds, maximum)
    XCTAssertNil(active?.routines.last?.completedTimeSeconds)

    let zeroService = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupPayloadAPIClient(
        active: activeRoutineGroupDTO(
          totalDurationSec: 0,
          completionRate: 0,
          routines: []
        )
      )
    )
    let zero = try await zeroService.fetchActiveRoutineGroup(identity: routineGroupIdentity)
    XCTAssertEqual(zero?.totalDurationSeconds, 0)
    XCTAssertEqual(zero?.completionRate, 0)
    XCTAssertEqual(zero?.routines, [])
  }

  func testActiveRejectsMissingMalformedAndDuplicateFields() async {
    let tooLarge = Int(Int32.max) + 1
    let invalidPayloads = [
      activeRoutineGroupDTO(routineGroupId: nil),
      activeRoutineGroupDTO(routineGroupId: 0),
      activeRoutineGroupDTO(title: nil),
      activeRoutineGroupDTO(title: " \n "),
      activeRoutineGroupDTO(totalDurationSec: nil),
      activeRoutineGroupDTO(totalDurationSec: -1),
      activeRoutineGroupDTO(totalDurationSec: tooLarge),
      activeRoutineGroupDTO(completionRate: nil),
      activeRoutineGroupDTO(completionRate: -1),
      activeRoutineGroupDTO(completionRate: 101),
      activeRoutineGroupDTO(routines: nil),
      activeRoutineGroupDTO(
        routines: [activeRoutineDTO(routineId: nil)]
      ),
      activeRoutineGroupDTO(
        routines: [activeRoutineDTO(routineId: 0)]
      ),
      activeRoutineGroupDTO(
        routines: [
          activeRoutineDTO(routineId: 31),
          activeRoutineDTO(routineId: 31),
        ]
      ),
      activeRoutineGroupDTO(
        routines: [activeRoutineDTO(title: nil)]
      ),
      activeRoutineGroupDTO(
        routines: [activeRoutineDTO(title: "\t")]
      ),
      activeRoutineGroupDTO(
        routines: [activeRoutineDTO(isCompleted: nil)]
      ),
      activeRoutineGroupDTO(
        routines: [activeRoutineDTO(completedTimeSec: -1)]
      ),
      activeRoutineGroupDTO(
        routines: [activeRoutineDTO(completedTimeSec: tooLarge)]
      ),
    ]

    for payload in invalidPayloads {
      let service = DefaultAccountRoutineGroupRemoteService(
        apiClient: RoutineGroupPayloadAPIClient(active: payload)
      )
      await assertRemoteError(.invalidResponse(reason: "")) {
        _ = try await service.fetchActiveRoutineGroup(identity: routineGroupIdentity)
      }
    }
  }

  func testTodayMapsPercentageWithoutOvervalidatingCountRatio()
    async throws {
    let maximum = Int(Int32.max)
    let service = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupPayloadAPIClient(
        today: todayRoutineGroupSummaryDTO(
          completedCount: 0,
          totalCount: maximum,
          completionRate: 77
        )
      )
    )

    let today = try await service.fetchTodayRoutineGroupSummary(identity: routineGroupIdentity)

    XCTAssertEqual(today?.completedCount, 0)
    XCTAssertEqual(today?.totalCount, maximum)
    XCTAssertEqual(today?.completionRate ?? -1, 0.77, accuracy: 0.000_001)
  }

  func testTodayRejectsMissingInvalidCountsAndPercentages() async {
    let tooLarge = Int(Int32.max) + 1
    let invalidPayloads = [
      todayRoutineGroupSummaryDTO(completedCount: nil),
      todayRoutineGroupSummaryDTO(totalCount: nil),
      todayRoutineGroupSummaryDTO(completionRate: nil),
      todayRoutineGroupSummaryDTO(completedCount: -1),
      todayRoutineGroupSummaryDTO(totalCount: -1),
      todayRoutineGroupSummaryDTO(completedCount: tooLarge),
      todayRoutineGroupSummaryDTO(totalCount: tooLarge),
      todayRoutineGroupSummaryDTO(
        completedCount: 2,
        totalCount: 1
      ),
      todayRoutineGroupSummaryDTO(completionRate: -1),
      todayRoutineGroupSummaryDTO(completionRate: 101),
    ]

    for payload in invalidPayloads {
      let service = DefaultAccountRoutineGroupRemoteService(
        apiClient: RoutineGroupPayloadAPIClient(today: payload)
      )
      await assertRemoteError(.invalidResponse(reason: "")) {
        _ = try await service.fetchTodayRoutineGroupSummary(identity: routineGroupIdentity)
      }
    }
  }

  func testOnlyExactNoActiveServerErrorMapsToNil() async throws {
    let noActive = APIError.server(
      statusCode: 404,
      code: "ROUTINE4005",
      message: "사용 중인 루틴이 없습니다."
    )
    let noActiveService = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupThrowingAPIClient(error: noActive)
    )

    let result = try await noActiveService.fetchActiveRoutineGroup(identity: routineGroupIdentity)
    XCTAssertNil(result)

    let lookalikes = [
      APIError.server(
        statusCode: 400,
        code: "ROUTINE4005",
        message: "wrong status"
      ),
      APIError.server(
        statusCode: 404,
        code: "ROUTINE4004",
        message: "wrong code"
      ),
      APIError.server(
        statusCode: 404,
        code: nil,
        message: "missing code"
      ),
      APIError.server(
        statusCode: 404,
        code: "ROUTINE4005",
        message: "wrong message"
      ),
      APIError.missingResult(
        code: "COMMON200",
        message: "missing result"
      ),
      APIError.decoding("malformed result"),
    ]

    for expected in lookalikes {
      let service = DefaultAccountRoutineGroupRemoteService(
        apiClient: RoutineGroupThrowingAPIClient(error: expected)
      )
      do {
        _ = try await service.fetchActiveRoutineGroup(identity: routineGroupIdentity)
        XCTFail("Expected \(expected), not an empty active result.")
      } catch let error as APIError {
        XCTAssertEqual(error, expected)
      } catch {
        XCTFail("Expected APIError, got \(error)")
      }
    }
  }

  func testOnlyExactNoTodayServerErrorMapsToNil() async throws {
    let noToday = APIError.server(
      statusCode: 404,
      code: "ROUTINE4005",
      message: "사용 중인 루틴이 없습니다."
    )
    let noTodayService = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupThrowingAPIClient(error: noToday)
    )

    let result = try await noTodayService.fetchTodayRoutineGroupSummary(
      identity: routineGroupIdentity
    )
    XCTAssertNil(result)

    let lookalikes = [
      APIError.server(
        statusCode: 400,
        code: "ROUTINE4005",
        message: "사용 중인 루틴이 없습니다."
      ),
      APIError.server(
        statusCode: 404,
        code: "ROUTINE4004",
        message: "사용 중인 루틴이 없습니다."
      ),
      APIError.server(
        statusCode: 404,
        code: "ROUTINE4005",
        message: "wrong message"
      ),
      APIError.missingResult(
        code: "COMMON200",
        message: "missing result"
      ),
      APIError.decoding("malformed result"),
    ]

    for expected in lookalikes {
      let service = DefaultAccountRoutineGroupRemoteService(
        apiClient: RoutineGroupThrowingAPIClient(error: expected)
      )
      do {
        _ = try await service.fetchTodayRoutineGroupSummary(identity: routineGroupIdentity)
        XCTFail("Expected \(expected), not an empty today result.")
      } catch let error as APIError {
        XCTAssertEqual(error, expected)
      } catch {
        XCTFail("Expected APIError, got \(error)")
      }
    }
  }

  func testNoActiveRejectsPresentNullOrUnexpectedResultField() async {
    let invalidBodies: [Data] = [
      Data(
        """
        {"isSuccess":false,"code":"ROUTINE4005",\
        "message":"사용 중인 루틴이 없습니다.","result":null}
        """.utf8
      ),
      Data(
        """
        {"isSuccess":false,"code":"ROUTINE4005",\
        "message":"사용 중인 루틴이 없습니다.","result":{}}
        """.utf8
      ),
      Data(
        """
        {"isSuccess":true,"code":"ROUTINE4005",\
        "message":"사용 중인 루틴이 없습니다."}
        """.utf8
      ),
      Data(
        """
        {"code":"ROUTINE4005",\
        "message":"사용 중인 루틴이 없습니다."}
        """.utf8
      ),
      Data(
        """
        {"isSuccess":"false","code":"ROUTINE4005",\
        "message":"사용 중인 루틴이 없습니다."}
        """.utf8
      ),
    ]

    for body in invalidBodies {
      let client = RoutineGroupRawResponseAPIClient(
        response: AccountBoundHTTPResponse(statusCode: 404, data: body)
      )
      let service = DefaultAccountRoutineGroupRemoteService(
        apiClient: client
      )

      let operations: [() async throws -> Void] = [
        {
          _ = try await service.fetchActiveRoutineGroup(identity: routineGroupIdentity)
        },
        {
          _ = try await service.fetchTodayRoutineGroupSummary(identity: routineGroupIdentity)
        },
      ]
      for operation in operations {
        do {
          try await operation()
          XCTFail("A present result must not become no-active.")
        } catch let error as APIError {
          guard case .server(statusCode: 404, _, _) = error else {
            return XCTFail("Expected a 404 server error, got \(error)")
          }
        } catch {
          XCTFail("Expected APIError, got \(error)")
        }
      }
    }
  }

  func testSuccessfulReadRejectsMissingNullAndMalformedResult() async {
    let invalidBodies = [
      Data(
        """
        {"isSuccess":true,"code":"COMMON200","message":"성공입니다."}
        """.utf8
      ),
      Data(
        """
        {"isSuccess":true,"code":"COMMON200",\
        "message":"성공입니다.","result":null}
        """.utf8
      ),
      Data(
        """
        {"isSuccess":true,"code":"COMMON200",\
        "message":"성공입니다.","result":[]}
        """.utf8
      ),
    ]

    for (index, body) in invalidBodies.enumerated() {
      let service = DefaultAccountRoutineGroupRemoteService(
        apiClient: RoutineGroupRawResponseAPIClient(
          response: AccountBoundHTTPResponse(statusCode: 200, data: body)
        )
      )
      let operations: [() async throws -> Void] = [
        {
          _ = try await service.fetchActiveRoutineGroup(
            identity: routineGroupIdentity
          )
        },
        {
          _ = try await service.fetchTodayRoutineGroupSummary(
            identity: routineGroupIdentity
          )
        },
      ]

      for operation in operations {
        do {
          try await operation()
          XCTFail("Invalid success result must not become empty.")
        } catch let error as APIError {
          if index < 2 {
            guard case .missingResult = error else {
              return XCTFail("Expected missingResult, got \(error)")
            }
          } else {
            guard case .decoding = error else {
              return XCTFail("Expected decoding, got \(error)")
            }
          }
        } catch {
          XCTFail("Expected APIError, got \(error)")
        }
      }
    }
  }

  func testRejectsInvalidRequestBeforeTransport() async {
    let client = RoutineGroupCallCountingAPIClient()
    let service = DefaultAccountRoutineGroupRemoteService(
      apiClient: client
    )

    await assertRemoteError(.invalidRequest) {
      _ = try await service.fetchRoutineGroups(memberID: 0)
    }
    await assertRemoteError(.invalidRequest) {
      _ = try await service.fetchRoutineGroupDetail(
        routineGroupID: 0,
        memberID: 98
      )
    }
    await assertRemoteError(.invalidRequest) {
      _ = try await service.fetchRoutineGroupDetail(
        routineGroupID: 12,
        memberID: -1
      )
    }
    await assertRemoteError(.invalidRequest) {
      _ = try await service.fetchActiveRoutineGroup(
        identity: AccountSessionIdentity(memberID: 0, sessionID: UUID())
      )
    }
    await assertRemoteError(.invalidRequest) {
      _ = try await service.fetchTodayRoutineGroupSummary(
        identity: AccountSessionIdentity(memberID: -1, sessionID: UUID())
      )
    }

    XCTAssertEqual(client.callCount, 0)
  }

  func testCancellationAndAccountAuthorizationChangeRemainDistinct()
    async {
    for error in [CancellationError(), APIError.cancelled] as [any Error] {
      let service = DefaultAccountRoutineGroupRemoteService(
        apiClient: RoutineGroupThrowingAPIClient(error: error)
      )

      do {
        _ = try await service.fetchRoutineGroups(memberID: 98)
        XCTFail("Expected cancellation.")
      } catch is CancellationError {
        continue
      } catch {
        XCTFail("Expected CancellationError, got \(error)")
      }
    }

    let changedAccountService = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupThrowingAPIClient(
        error: AccountAuthorizationContextError.memberMismatch
      )
    )
    await assertRemoteError(.accountAuthorizationChanged) {
      _ = try await changedAccountService.fetchRoutineGroups(memberID: 98)
    }

    await assertRemoteError(.accountAuthorizationChanged) {
      _ = try await changedAccountService.fetchActiveRoutineGroup(identity: routineGroupIdentity)
    }
    await assertRemoteError(.accountAuthorizationChanged) {
      _ = try await changedAccountService.fetchTodayRoutineGroupSummary(
        identity: routineGroupIdentity
      )
    }

    let cancelledService = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupThrowingAPIClient(error: APIError.cancelled)
    )
    for operation in [
      {
        _ = try await cancelledService.fetchActiveRoutineGroup(identity: routineGroupIdentity)
      },
      {
        _ = try await cancelledService.fetchTodayRoutineGroupSummary(
          identity: routineGroupIdentity
        )
      },
    ] {
      do {
        try await operation()
        XCTFail("Expected cancellation.")
      } catch is CancellationError {
        continue
      } catch {
        XCTFail("Expected CancellationError, got \(error)")
      }
    }
  }

  func testDetailNotFoundPreservesServerErrorForPresentation()
    async {
    let serverError = APIError.server(
      statusCode: 404,
      code: "ROUTINE_GROUP404",
      message: "루틴 그룹을 찾을 수 없습니다."
    )
    let service = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupThrowingAPIClient(error: serverError)
    )

    do {
      _ = try await service.fetchRoutineGroupDetail(
        routineGroupID: 12,
        memberID: 98
      )
      XCTFail("Expected a 404 server error.")
    } catch let error as APIError {
      XCTAssertEqual(error, serverError)
    } catch {
      XCTFail("Expected APIError, got \(error)")
    }
  }

  func testCancellationAfterTransportCannotPublishPayload() async {
    let gate = RoutineGroupRequestGate()
    let service = DefaultAccountRoutineGroupRemoteService(
      apiClient: RoutineGroupDeferredAPIClient(gate: gate)
    )
    let task = _Concurrency.Task {
      try await service.fetchRoutineGroups(memberID: 98)
    }

    await gate.waitUntilRequestArrives()
    task.cancel()
    await gate.release()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation.")
    } catch is CancellationError {
      // Expected.
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }
  }

  func testActiveAndTodayCancellationAfterTransportCannotPublishPayload()
    async {
    let operations: [
      (DefaultAccountRoutineGroupRemoteService) async throws -> Void
    ] = [
      { service in
        _ = try await service.fetchActiveRoutineGroup(identity: routineGroupIdentity)
      },
      { service in
        _ = try await service.fetchTodayRoutineGroupSummary(identity: routineGroupIdentity)
      },
    ]

    for operation in operations {
      let gate = RoutineGroupRequestGate()
      let service = DefaultAccountRoutineGroupRemoteService(
        apiClient: RoutineGroupDeferredAPIClient(gate: gate)
      )
      let task = _Concurrency.Task {
        try await operation(service)
      }

      await gate.waitUntilRequestArrives()
      task.cancel()
      await gate.release()

      do {
        try await task.value
        XCTFail("Expected cancellation.")
      } catch is CancellationError {
        continue
      } catch {
        XCTFail("Expected CancellationError, got \(error)")
      }
    }
  }

  private func assertRemoteError(
    _ expected: AccountRoutineGroupRemoteError,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected).")
    } catch let error as AccountRoutineGroupRemoteError {
      XCTAssertTrue(
        Self.isSameCase(error, expected),
        "Expected \(expected), got \(error)"
      )
    } catch {
      XCTFail("Expected AccountRoutineGroupRemoteError, got \(error)")
    }
  }

  private static func isSameCase(
    _ lhs: AccountRoutineGroupRemoteError,
    _ rhs: AccountRoutineGroupRemoteError
  ) -> Bool {
    switch (lhs, rhs) {
    case (.invalidRequest, .invalidRequest),
      (.invalidResponse, .invalidResponse),
      (.accountAuthorizationChanged, .accountAuthorizationChanged):
      true
    default:
      false
    }
  }

  nonisolated private func makeStubbedService(
    additionalPlugins: [any PluginType & Sendable] = []
  ) -> DefaultAccountRoutineGroupRemoteService {
    let client = DefaultAPIClient(
      tokenProvider: RoutineGroupAccessTokenProvider(),
      providerFactory: MoyaProviderFactory(
        endpointBuilder: { target in
          let endpoint = MoyaProvider<MultiTarget>
            .defaultEndpointMapping(for: target)
          return Endpoint(
            url: endpoint.url,
            sampleResponseClosure: {
              .networkResponse(200, target.sampleData)
            },
            method: endpoint.method,
            task: endpoint.task,
            httpHeaderFields: endpoint.httpHeaderFields
          )
        },
        stubBuilder: { _ in .immediate },
        additionalPlugins: additionalPlugins
      )
    )
    return DefaultAccountRoutineGroupRemoteService(apiClient: client)
  }
}

nonisolated private func routineGroupSummaryDTO(
  routineGroupId: Int64? = 12,
  title: String? = "아침 루틴",
  isActive: Bool? = true,
  routineCount: Int? = 2,
  totalDurationSecond: Int? = 180
) -> RoutineGroupSummaryResponseDTO {
  RoutineGroupSummaryResponseDTO(
    routineGroupId: routineGroupId,
    title: title,
    isActive: isActive,
    routineCount: routineCount,
    totalDurationSecond: totalDurationSecond
  )
}

nonisolated private func routineGroupDetailDTO(
  routineGroupId: Int64? = 12,
  title: String? = "아침 루틴",
  description: String? = "하루 시작",
  alarmDays: String? = "MON,TUE,WED,THU,FRI",
  alarmTime: String? = "07:30",
  weatherNotificationEnabled: Bool? = true,
  routines: [RoutineGroupRoutineResponseDTO]? = [
    routineDTO(),
  ]
) -> RoutineGroupDetailResponseDTO {
  RoutineGroupDetailResponseDTO(
    routineGroupId: routineGroupId,
    title: title,
    description: description,
    alarmDays: alarmDays,
    alarmTime: alarmTime,
    weatherNotificationEnabled: weatherNotificationEnabled,
    routines: routines
  )
}

nonisolated private func routineDTO(
  routineId: Int64? = 31,
  title: String? = "물 마시기",
  type: String? = "CHECK",
  durationSecond: Int? = 30,
  steps: [RoutineGroupStepResponseDTO]? = []
) -> RoutineGroupRoutineResponseDTO {
  RoutineGroupRoutineResponseDTO(
    routineId: routineId,
    title: title,
    type: type,
    durationSecond: durationSecond,
    steps: steps
  )
}

nonisolated private func stepDTO(
  stepId: Int64? = 41,
  content: String? = "준비하기",
  orderIndex: Int? = 0
) -> RoutineGroupStepResponseDTO {
  RoutineGroupStepResponseDTO(
    stepId: stepId,
    content: content,
    orderIndex: orderIndex
  )
}

nonisolated private func activeRoutineGroupDTO(
  routineGroupId: Int64? = 12,
  title: String? = "아침 루틴",
  totalDurationSec: Int? = 180,
  completionRate: Int? = 50,
  routines: [ActiveRoutineResponseDTO]? = [
    activeRoutineDTO(),
  ]
) -> ActiveRoutineGroupResponseDTO {
  ActiveRoutineGroupResponseDTO(
    routineGroupId: routineGroupId,
    title: title,
    totalDurationSec: totalDurationSec,
    completionRate: completionRate,
    routines: routines
  )
}

nonisolated private func activeRoutineDTO(
  routineId: Int64? = 31,
  title: String? = "물 마시기",
  isCompleted: Bool? = true,
  completedTimeSec: Int? = 30
) -> ActiveRoutineResponseDTO {
  ActiveRoutineResponseDTO(
    routineId: routineId,
    title: title,
    isCompleted: isCompleted,
    completedTimeSec: completedTimeSec
  )
}

nonisolated private func todayRoutineGroupSummaryDTO(
  completedCount: Int? = 1,
  totalCount: Int? = 2,
  completionRate: Int? = 50
) -> TodayRoutineGroupSummaryResponseDTO {
  TodayRoutineGroupSummaryResponseDTO(
    completedCount: completedCount,
    totalCount: totalCount,
    completionRate: completionRate
  )
}

nonisolated private struct RoutineGroupTestEnvelope<Payload: Encodable>:
  Encodable {
  let isSuccess = true
  let code = "COMMON200"
  let message = "성공입니다."
  let result: Payload
}

nonisolated private func routineGroupResponseData<Payload: Encodable>(
  _ payload: Payload
) throws -> Data {
  try JSONEncoder().encode(RoutineGroupTestEnvelope(result: payload))
}

nonisolated private func routineGroupErrorResponseData(
  code: String?,
  message: String
) throws -> Data {
  var object: [String: Any] = [
    "isSuccess": false,
    "message": message,
  ]
  if let code {
    object["code"] = code
  }
  return try JSONSerialization.data(withJSONObject: object)
}

nonisolated private final class RoutineGroupAccessTokenProvider:
  AccountBoundAccessTokenProviding {
  private let context = AccountAuthorizationContext(
    memberID: routineGroupIdentity.memberID,
    accessToken: "access-token",
    sessionID: routineGroupIdentity.sessionID
  )

  var accessToken: String? {
    context.accessToken
  }

  func authorizationContext(
    forMemberID memberID: Int64
  ) -> AccountAuthorizationContext? {
    context.memberID == memberID ? context : nil
  }
}

nonisolated private final class RoutineGroupRequestCapturePlugin:
  PluginType,
  @unchecked Sendable {
  private let lock = NSLock()
  private var capturedRequests: [URLRequest] = []

  var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return capturedRequests
  }

  func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
    lock.lock()
    capturedRequests.append(request)
    lock.unlock()
    return request
  }
}

nonisolated private final class RoutineGroupPayloadAPIClient:
  AccountBoundRawResponseClient,
  @unchecked Sendable {
  private let summaries: [RoutineGroupSummaryResponseDTO]
  private let detail: RoutineGroupDetailResponseDTO
  private let active: ActiveRoutineGroupResponseDTO
  private let today: TodayRoutineGroupSummaryResponseDTO

  init(
    summaries: [RoutineGroupSummaryResponseDTO] = [
      routineGroupSummaryDTO(),
    ],
    detail: RoutineGroupDetailResponseDTO = routineGroupDetailDTO(),
    active: ActiveRoutineGroupResponseDTO = activeRoutineGroupDTO(),
    today: TodayRoutineGroupSummaryResponseDTO =
      todayRoutineGroupSummaryDTO()
  ) {
    self.summaries = summaries
    self.detail = detail
    self.active = active
    self.today = today
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    throw APIError.invalidRequest("Expected an account-bound request.")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    guard memberID == routineGroupIdentity.memberID,
          let target = target as? RoutineGroupTarget else {
      throw AccountAuthorizationContextError.memberMismatch
    }

    let response: Any
    switch target {
    case .list:
      response = summaries
    case .detail:
      response = detail
    case .active:
      response = active
    case .today:
      response = today
    }

    guard let payload = response as? Payload else {
      throw APIError.decoding("Unexpected routine-group payload type.")
    }
    return payload
  }

  func requestResponse<Target: MoruTargetType>(
    _ target: Target,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> AccountBoundHTTPResponse {
    guard identity == routineGroupIdentity,
          let target = target as? RoutineGroupTarget else {
      throw AccountAuthorizationContextError.memberMismatch
    }

    let data: Data
    switch target {
    case .active:
      data = try routineGroupResponseData(active)
    case .today:
      data = try routineGroupResponseData(today)
    case .list, .detail:
      throw APIError.invalidRequest("Expected Active/Today raw request.")
    }
    return AccountBoundHTTPResponse(statusCode: 200, data: data)
  }

  func requestVoid<Target: MoruTargetType>(
    _ target: Target
  ) async throws {
    throw APIError.invalidRequest("Unexpected void request.")
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    throw APIError.invalidRequest("Unexpected data request.")
  }
}

nonisolated private final class RoutineGroupCallCountingAPIClient:
  AccountBoundRawResponseClient,
  @unchecked Sendable {
  private let lock = NSLock()
  private var requestCallCount = 0

  var callCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return requestCallCount
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  func requestResponse<Target: MoruTargetType>(
    _ target: Target,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> AccountBoundHTTPResponse {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  func requestVoid<Target: MoruTargetType>(
    _ target: Target
  ) async throws {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  private func recordCall() {
    lock.lock()
    requestCallCount += 1
    lock.unlock()
  }
}

nonisolated private final class RoutineGroupThrowingAPIClient:
  AccountBoundRawResponseClient,
  @unchecked Sendable {
  private let error: any Error

  init(error: any Error) {
    self.error = error
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    throw error
  }

  func requestResponse<Target: MoruTargetType>(
    _ target: Target,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> AccountBoundHTTPResponse {
    guard identity == routineGroupIdentity else {
      throw AccountAuthorizationContextError.memberMismatch
    }
    if case .server(let statusCode, let code, let message) = error as? APIError {
      return AccountBoundHTTPResponse(
        statusCode: statusCode,
        data: try routineGroupErrorResponseData(code: code, message: message)
      )
    }
    throw error
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    throw error
  }

  func requestVoid<Target: MoruTargetType>(
    _ target: Target
  ) async throws {
    throw error
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    throw error
  }
}

nonisolated private final class RoutineGroupRawResponseAPIClient:
  AccountBoundRawResponseClient,
  @unchecked Sendable {
  private let response: AccountBoundHTTPResponse

  init(response: AccountBoundHTTPResponse) {
    self.response = response
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    throw APIError.invalidRequest("Expected raw response request.")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    throw APIError.invalidRequest("Expected raw response request.")
  }

  func requestResponse<Target: MoruTargetType>(
    _ target: Target,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> AccountBoundHTTPResponse {
    guard identity == routineGroupIdentity else {
      throw AccountAuthorizationContextError.memberMismatch
    }
    return response
  }

  func requestVoid<Target: MoruTargetType>(
    _ target: Target
  ) async throws {
    throw APIError.invalidRequest("Unexpected void request.")
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    throw APIError.invalidRequest("Unexpected data request.")
  }
}

nonisolated private final class RoutineGroupDeferredAPIClient:
  AccountBoundRawResponseClient,
  Sendable {
  private let gate: RoutineGroupRequestGate

  init(gate: RoutineGroupRequestGate) {
    self.gate = gate
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    throw APIError.invalidRequest("Expected an account-bound request.")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    await gate.arrive()
    guard let target = target as? RoutineGroupTarget else {
      throw APIError.invalidRequest("Unexpected request target.")
    }

    let response: Any
    switch target {
    case .list:
      response = [routineGroupSummaryDTO()]
    case .detail:
      response = routineGroupDetailDTO()
    case .active:
      response = activeRoutineGroupDTO()
    case .today:
      response = todayRoutineGroupSummaryDTO()
    }

    guard let payload = response as? Payload else {
      throw APIError.decoding("Unexpected routine-group payload type.")
    }
    return payload
  }

  func requestResponse<Target: MoruTargetType>(
    _ target: Target,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> AccountBoundHTTPResponse {
    await gate.arrive()
    guard identity == routineGroupIdentity,
          let target = target as? RoutineGroupTarget else {
      throw AccountAuthorizationContextError.memberMismatch
    }

    let data: Data
    switch target {
    case .active:
      data = try routineGroupResponseData(activeRoutineGroupDTO())
    case .today:
      data = try routineGroupResponseData(
        todayRoutineGroupSummaryDTO()
      )
    case .list, .detail:
      throw APIError.invalidRequest("Expected Active/Today raw request.")
    }
    return AccountBoundHTTPResponse(statusCode: 200, data: data)
  }

  func requestVoid<Target: MoruTargetType>(
    _ target: Target
  ) async throws {
    throw APIError.invalidRequest("Unexpected void request.")
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    throw APIError.invalidRequest("Unexpected data request.")
  }
}

private actor RoutineGroupRequestGate {
  private var requestArrived = false
  private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func arrive() async {
    requestArrived = true
    let waiters = arrivalWaiters
    arrivalWaiters.removeAll()
    waiters.forEach { $0.resume() }

    await withCheckedContinuation { continuation in
      releaseWaiters.append(continuation)
    }
  }

  func waitUntilRequestArrives() async {
    guard !requestArrived else {
      return
    }
    await withCheckedContinuation { continuation in
      arrivalWaiters.append(continuation)
    }
  }

  func release() {
    let waiters = releaseWaiters
    releaseWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }
}
