//
//  RoutineGroupRemoteContractTests.swift
//  MoruTests
//

import Foundation
import XCTest

import Moya

@testable import Moru

@MainActor
final class RoutineGroupRemoteContractTests: XCTestCase {
  func testTargetsMatchSwaggerAndSamplesDecode() throws {
    let list = RoutineGroupTarget.list
    let detail = RoutineGroupTarget.detail(routineGroupID: 12)

    XCTAssertEqual(list.path, "/routine-groups")
    XCTAssertEqual(detail.path, "/routine-groups/12")
    XCTAssertEqual(list.method, .get)
    XCTAssertEqual(detail.method, .get)
    XCTAssertEqual(list.authenticationRequirement, .bearer)
    XCTAssertEqual(detail.authenticationRequirement, .bearer)

    for target in [list, detail] {
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

    XCTAssertEqual(listEnvelope.result?.first?.routineGroupId, 12)
    XCTAssertEqual(detailEnvelope.result?.routineGroupId, 12)
    XCTAssertEqual(
      detailEnvelope.result?.routines?.first?.steps?.first?.stepId,
      41
    )
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
      capture.requests.compactMap(\.url?.path),
      ["/routine-groups", "/routine-groups/12"]
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
      await assertRemoteError(.invalidResponse) {
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
      await assertRemoteError(.invalidResponse) {
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
      await assertRemoteError(.invalidResponse) {
        _ = try await service.fetchRoutineGroupDetail(
          routineGroupID: 12,
          memberID: 98
        )
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

  private func assertRemoteError(
    _ expected: AccountRoutineGroupRemoteError,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected).")
    } catch let error as AccountRoutineGroupRemoteError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Expected AccountRoutineGroupRemoteError, got \(error)")
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

nonisolated private final class RoutineGroupAccessTokenProvider:
  AccountBoundAccessTokenProviding {
  private let context = AccountAuthorizationContext(
    memberID: 98,
    accessToken: "access-token",
    sessionID: UUID()
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
  AccountBoundAPIClient,
  @unchecked Sendable {
  private let summaries: [RoutineGroupSummaryResponseDTO]
  private let detail: RoutineGroupDetailResponseDTO

  init(
    summaries: [RoutineGroupSummaryResponseDTO] = [
      routineGroupSummaryDTO(),
    ],
    detail: RoutineGroupDetailResponseDTO = routineGroupDetailDTO()
  ) {
    self.summaries = summaries
    self.detail = detail
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
    guard memberID == 98,
          let target = target as? RoutineGroupTarget else {
      throw AccountAuthorizationContextError.memberMismatch
    }

    let response: Any
    switch target {
    case .list:
      response = summaries
    case .detail:
      response = detail
    }

    guard let payload = response as? Payload else {
      throw APIError.decoding("Unexpected routine-group payload type.")
    }
    return payload
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
  AccountBoundAPIClient,
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
  AccountBoundAPIClient,
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

nonisolated private final class RoutineGroupDeferredAPIClient:
  AccountBoundAPIClient,
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
    let response = [routineGroupSummaryDTO()]
    guard let payload = response as? Payload else {
      throw APIError.decoding("Unexpected routine-group payload type.")
    }
    return payload
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
