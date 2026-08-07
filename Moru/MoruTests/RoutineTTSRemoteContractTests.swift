//
//  RoutineTTSRemoteContractTests.swift
//  MoruTests
//

import Foundation
import XCTest

import Moya

@testable import Moru

@MainActor
final class RoutineTTSRemoteContractTests: XCTestCase {
  func testTargetsMatchSwaggerAndSamplesDecode() throws {
    let create = RoutineGroupTarget.create(
      RoutineGroupCreateRequestDTO(
        title: "아침 루틴",
        description: "천천히 하루를 시작해요",
        alarmDays: "MON,TUE,WED,THU,FRI",
        alarmTime: "07:30",
        weatherNotificationEnabled: true,
        routines: [
          RoutineCreateRequestDTO(
            title: "물 마시기",
            type: "CHECK",
            durationSecond: 30
          ),
        ]
      )
    )
    let delete = RoutineGroupTarget.delete(routineGroupID: 12)
    let manifest = RoutineTTSTarget.manifest(routineGroupID: 12)

    XCTAssertEqual(create.path, "/routine-groups")
    XCTAssertEqual(create.method, .post)
    XCTAssertEqual(delete.path, "/routine-groups/12")
    XCTAssertEqual(delete.method, .delete)
    XCTAssertEqual(manifest.path, "/routine-tts/12/tts")
    XCTAssertEqual(manifest.method, .get)
    XCTAssertEqual(create.authenticationRequirement, .bearer)
    XCTAssertEqual(delete.authenticationRequirement, .bearer)
    XCTAssertEqual(manifest.authenticationRequirement, .bearer)

    guard case .requestJSONEncodable = create.task else {
      return XCTFail("Expected a JSON-encoded create request.")
    }
    for target in [delete] {
      guard case .requestPlain = target.task else {
        return XCTFail("Expected a body-free delete request.")
      }
    }
    guard case .requestPlain = manifest.task else {
      return XCTFail("Expected a body-free TTS request.")
    }

    let decoder = JSONDecoder()
    let createEnvelope = try decoder.decode(
      APIResponse<RoutineGroupDetailResponseDTO>.self,
      from: create.sampleData
    )
    let deleteEnvelope = try decoder.decode(
      APIResponse<RoutineGroupDeleteResponseDTO>.self,
      from: delete.sampleData
    )
    let manifestEnvelope = try decoder.decode(
      APIResponse<[RoutineTTSResponseDTO]>.self,
      from: manifest.sampleData
    )

    XCTAssertEqual(createEnvelope.result?.routineGroupId, 12)
    XCTAssertEqual(deleteEnvelope.result?.routineId, 12)
    XCTAssertEqual(manifestEnvelope.result?.first?.routineId, 31)
    XCTAssertEqual(
      manifestEnvelope.result?.first?.steps?.first?.ttsStatus,
      "COMPLETED"
    )
  }

  func testCreateFetchAndDeleteUseAccountBindingAndExactRequests()
    async throws {
    let capture = RoutineTTSRequestCapturePlugin()
    let service = makeStubbedService(additionalPlugins: [capture])
    let localRoutineID = UUID()
    let localStepID = UUID()

    let creation = try await service.createRoutineGroup(
      ServerRoutineGroupCreationRequest(
        localRoutineID: localRoutineID,
        title: "  아침 루틴  ",
        description: "  천천히 하루를 시작해요  ",
        alarmDaysRaw: "MON,TUE,WED,THU,FRI",
        alarmTimeRaw: "07:30",
        weatherNotificationEnabled: true,
        routines: [
          ServerRoutineCreationRequest(
            localStepID: localStepID,
            title: "  물 마시기  ",
            type: .check,
            durationSeconds: 30
          ),
        ]
      ),
      memberID: 98
    )
    let manifest = try await service.fetchRoutineTTS(
      routineGroupID: creation.routineGroupID,
      memberID: 98
    )
    let deletion = try await service.deleteRoutineGroup(
      routineGroupID: creation.routineGroupID,
      memberID: 98
    )

    XCTAssertEqual(creation.localRoutineID, localRoutineID)
    XCTAssertEqual(creation.routineGroupID, 12)
    XCTAssertEqual(creation.routines.first?.localStepID, localStepID)
    XCTAssertEqual(creation.routines.first?.routineID, 31)
    XCTAssertEqual(creation.routines.first?.steps.first?.stepID, 41)
    XCTAssertEqual(manifest.routineGroupID, 12)
    XCTAssertEqual(manifest.routines.first?.routineID, 31)
    XCTAssertEqual(
      manifest.routines.first?.steps.first?.audioURL,
      URL(string: "https://audio.example.com/41.mp3")
    )
    XCTAssertEqual(deletion.requestedRoutineGroupID, 12)
    XCTAssertEqual(deletion.serverAcknowledgedRoutineID, 12)

    let requests = capture.requests
    XCTAssertEqual(
      requests.compactMap(\.url?.path),
      [
        "/routine-groups",
        "/routine-tts/12/tts",
        "/routine-groups/12",
      ]
    )
    XCTAssertTrue(
      requests.allSatisfy {
        $0.value(forHTTPHeaderField: "Authorization")
          == "Bearer access-token"
      }
    )
    XCTAssertEqual(requests.map(\.httpMethod), ["POST", "GET", "DELETE"])
    XCTAssertNil(requests[1].httpBody)
    XCTAssertNil(requests[2].httpBody)

    let body = try XCTUnwrap(requests[0].httpBody)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: body) as? [String: Any]
    )
    XCTAssertEqual(json["title"] as? String, "아침 루틴")
    XCTAssertEqual(
      json["description"] as? String,
      "천천히 하루를 시작해요"
    )
    XCTAssertEqual(
      json["alarmDays"] as? String,
      "MON,TUE,WED,THU,FRI"
    )
    XCTAssertEqual(json["alarmTime"] as? String, "07:30")
    XCTAssertEqual(
      json["weatherNotificationEnabled"] as? Bool,
      true
    )
    let routines = try XCTUnwrap(
      json["routines"] as? [[String: Any]]
    )
    XCTAssertEqual(routines.count, 1)
    XCTAssertEqual(routines[0]["title"] as? String, "물 마시기")
    XCTAssertEqual(routines[0]["type"] as? String, "CHECK")
    XCTAssertEqual(routines[0]["durationSecond"] as? Int, 30)
    XCTAssertNil(json["localRoutineID"])
    XCTAssertNil(routines[0]["localStepID"])
  }

  func testResponseDTOsDecodeSwaggerFieldsAsOptional() throws {
    let decoder = JSONDecoder()
    let routine = try decoder.decode(
      RoutineTTSResponseDTO.self,
      from: Data("{}".utf8)
    )
    let step = try decoder.decode(
      RoutineTTSStepResponseDTO.self,
      from: Data("{}".utf8)
    )
    let deletion = try decoder.decode(
      RoutineGroupDeleteResponseDTO.self,
      from: Data("{}".utf8)
    )

    XCTAssertNil(routine.routineId)
    XCTAssertNil(routine.title)
    XCTAssertNil(routine.type)
    XCTAssertNil(routine.steps)
    XCTAssertNil(step.stepId)
    XCTAssertNil(step.content)
    XCTAssertNil(step.ttsIntro)
    XCTAssertNil(step.ttsStatus)
    XCTAssertNil(step.s3Url)
    XCTAssertNil(deletion.routineId)
  }

  func testCreationMapsAllItemTypesAndSortsGeneratedSteps()
    async throws {
    let localRoutineID = UUID()
    let localStepIDs = [UUID(), UUID(), UUID()]
    let request = ServerRoutineGroupCreationRequest(
      localRoutineID: localRoutineID,
      title: "아침 루틴",
      description: nil,
      alarmDaysRaw: nil,
      alarmTimeRaw: nil,
      weatherNotificationEnabled: false,
      routines: [
        creationRequest(
          localStepID: localStepIDs[0],
          title: "확인",
          type: .check,
          durationSeconds: 30
        ),
        creationRequest(
          localStepID: localStepIDs[1],
          title: "타이머",
          type: .timer,
          durationSeconds: 60
        ),
        creationRequest(
          localStepID: localStepIDs[2],
          title: "입력",
          type: .input,
          durationSeconds: 90
        ),
      ]
    )
    let service = DefaultAccountRoutineTTSRemoteService(
      apiClient: RoutineTTSPayloadAPIClient(
        creation: creationDetailDTO(
          routines: [
            creationRoutineDTO(
              routineId: 1,
              title: "확인",
              type: "CHECK",
              durationSecond: 30,
              steps: [
                creationStepDTO(stepId: 12, orderIndex: 2),
                creationStepDTO(stepId: 10, orderIndex: 0),
                creationStepDTO(stepId: 11, orderIndex: 1),
              ]
            ),
            creationRoutineDTO(
              routineId: 2,
              title: "타이머",
              type: "TIMER",
              durationSecond: 60,
              steps: [
                creationStepDTO(stepId: 20),
              ]
            ),
            creationRoutineDTO(
              routineId: 3,
              title: "입력",
              type: "INPUT",
              durationSecond: 90,
              steps: [
                creationStepDTO(stepId: 30),
              ]
            ),
          ]
        )
      )
    )

    let result = try await service.createRoutineGroup(
      request,
      memberID: 98
    )

    XCTAssertEqual(result.localRoutineID, localRoutineID)
    XCTAssertEqual(result.routines.map(\.localStepID), localStepIDs)
    XCTAssertEqual(
      result.routines.map(\.type),
      [.check, .timer, .input]
    )
    XCTAssertEqual(
      result.routines.first?.steps.map(\.stepID),
      [10, 11, 12]
    )
  }

  func testManifestMapsStatusesOptionalFieldsAndUnknownValues()
    async throws {
    let service = DefaultAccountRoutineTTSRemoteService(
      apiClient: RoutineTTSPayloadAPIClient(
        manifest: [
          ttsRoutineDTO(
            routineId: 31,
            title: "  물 마시기  ",
            type: "FUTURE_TYPE",
            steps: [
              ttsStepDTO(
                stepId: 41,
                content: nil,
                ttsIntro: nil,
                ttsStatus: "PENDING",
                s3Url: nil
              ),
              ttsStepDTO(
                stepId: 42,
                ttsStatus: "FAILED",
                s3Url: nil
              ),
              ttsStepDTO(
                stepId: 43,
                ttsStatus: "FUTURE_STATUS",
                s3Url: nil
              ),
              ttsStepDTO(
                stepId: 44,
                ttsStatus: "COMPLETED",
                s3Url: "https://audio.example.com/44.mp3"
              ),
            ]
          ),
        ]
      )
    )

    let manifest = try await service.fetchRoutineTTS(
      routineGroupID: 12,
      memberID: 98
    )

    XCTAssertEqual(manifest.routines.first?.title, "물 마시기")
    XCTAssertEqual(
      manifest.routines.first?.type,
      .unknown("FUTURE_TYPE")
    )
    XCTAssertEqual(
      manifest.routines.first?.steps.map(\.status),
      [
        .pending,
        .failed,
        .unknown("FUTURE_STATUS"),
        .completed,
      ]
    )
    XCTAssertNil(manifest.routines.first?.steps.first?.content)
    XCTAssertNil(manifest.routines.first?.steps.first?.synthesizedIntro)
  }

  func testEmptyManifestAndMissingDeleteAcknowledgementAreValid()
    async throws {
    let service = DefaultAccountRoutineTTSRemoteService(
      apiClient: RoutineTTSPayloadAPIClient(
        deletion: RoutineGroupDeleteResponseDTO(routineId: nil),
        manifest: []
      )
    )

    let manifest = try await service.fetchRoutineTTS(
      routineGroupID: 12,
      memberID: 98
    )
    let deletion = try await service.deleteRoutineGroup(
      routineGroupID: 12,
      memberID: 98
    )

    XCTAssertEqual(manifest.routines, [])
    XCTAssertNil(deletion.serverAcknowledgedRoutineID)
  }

  func testInvalidRequestsStopBeforeTransport() async {
    let client = RoutineTTSCallCountingAPIClient()
    let service = DefaultAccountRoutineTTSRemoteService(
      apiClient: client
    )
    let validRequest = creationGroupRequest()
    let duplicateStepID = UUID()
    let invalidCreationRequests = [
      ServerRoutineGroupCreationRequest(
        localRoutineID: UUID(),
        title: " ",
        description: nil,
        alarmDaysRaw: nil,
        alarmTimeRaw: nil,
        weatherNotificationEnabled: false,
        routines: validRequest.routines
      ),
      ServerRoutineGroupCreationRequest(
        localRoutineID: UUID(),
        title: "아침",
        description: nil,
        alarmDaysRaw: nil,
        alarmTimeRaw: "7:30",
        weatherNotificationEnabled: false,
        routines: validRequest.routines
      ),
      ServerRoutineGroupCreationRequest(
        localRoutineID: UUID(),
        title: "아침",
        description: nil,
        alarmDaysRaw: nil,
        alarmTimeRaw: nil,
        weatherNotificationEnabled: false,
        routines: []
      ),
      ServerRoutineGroupCreationRequest(
        localRoutineID: UUID(),
        title: "아침",
        description: nil,
        alarmDaysRaw: nil,
        alarmTimeRaw: nil,
        weatherNotificationEnabled: false,
        routines: [
          creationRequest(
            localStepID: duplicateStepID,
            durationSeconds: 30
          ),
          creationRequest(
            localStepID: duplicateStepID,
            durationSeconds: 30
          ),
        ]
      ),
      ServerRoutineGroupCreationRequest(
        localRoutineID: UUID(),
        title: "아침",
        description: nil,
        alarmDaysRaw: nil,
        alarmTimeRaw: nil,
        weatherNotificationEnabled: false,
        routines: [
          creationRequest(durationSeconds: 0),
        ]
      ),
    ]

    await assertRemoteError(.invalidRequest) {
      _ = try await service.createRoutineGroup(
        validRequest,
        memberID: 0
      )
    }
    for request in invalidCreationRequests {
      await assertRemoteError(.invalidRequest) {
        _ = try await service.createRoutineGroup(
          request,
          memberID: 98
        )
      }
    }
    await assertRemoteError(.invalidRequest) {
      _ = try await service.fetchRoutineTTS(
        routineGroupID: 0,
        memberID: 98
      )
    }
    await assertRemoteError(.invalidRequest) {
      _ = try await service.deleteRoutineGroup(
        routineGroupID: 12,
        memberID: 0
      )
    }

    XCTAssertEqual(client.callCount, 0)
  }

  func testCreationRejectsMismatchedAndDuplicateResponseIdentity()
    async {
    let request = creationGroupRequest()
    let invalidResponses = [
      creationDetailDTO(routineGroupId: nil),
      creationDetailDTO(routineGroupId: 0),
      creationDetailDTO(routines: nil),
      creationDetailDTO(routines: []),
      creationDetailDTO(
        routines: [
          creationRoutineDTO(routineId: 0),
        ]
      ),
      creationDetailDTO(
        routines: [
          creationRoutineDTO(title: "다른 제목"),
        ]
      ),
      creationDetailDTO(
        routines: [
          creationRoutineDTO(type: "TIMER"),
        ]
      ),
      creationDetailDTO(
        routines: [
          creationRoutineDTO(durationSecond: 31),
        ]
      ),
      creationDetailDTO(
        routines: [
          creationRoutineDTO(steps: nil),
        ]
      ),
      creationDetailDTO(
        routines: [
          creationRoutineDTO(
            steps: [
              creationStepDTO(stepId: 41, orderIndex: 0),
              creationStepDTO(stepId: 41, orderIndex: 1),
            ]
          ),
        ]
      ),
      creationDetailDTO(
        routines: [
          creationRoutineDTO(
            steps: [
              creationStepDTO(stepId: 41, orderIndex: 0),
              creationStepDTO(stepId: 42, orderIndex: 0),
            ]
          ),
        ]
      ),
    ]

    for response in invalidResponses {
      let service = DefaultAccountRoutineTTSRemoteService(
        apiClient: RoutineTTSPayloadAPIClient(creation: response)
      )
      await assertRemoteError(.invalidResponse) {
        _ = try await service.createRoutineGroup(
          request,
          memberID: 98
        )
      }
    }
  }

  func testManifestRejectsMissingIdentityInvalidURLsAndDuplicates()
    async {
    let invalidResponses: [[RoutineTTSResponseDTO]] = [
      [ttsRoutineDTO(routineId: nil)],
      [ttsRoutineDTO(routineId: 0)],
      [
        ttsRoutineDTO(routineId: 1),
        ttsRoutineDTO(routineId: 1),
      ],
      [ttsRoutineDTO(steps: nil)],
      [
        ttsRoutineDTO(
          steps: [ttsStepDTO(stepId: nil)]
        ),
      ],
      [
        ttsRoutineDTO(
          steps: [ttsStepDTO(stepId: 0)]
        ),
      ],
      [
        ttsRoutineDTO(
          steps: [
            ttsStepDTO(stepId: 41),
            ttsStepDTO(stepId: 41),
          ]
        ),
      ],
      [
        ttsRoutineDTO(
          steps: [ttsStepDTO(ttsStatus: nil)]
        ),
      ],
      [
        ttsRoutineDTO(
          steps: [
            ttsStepDTO(
              ttsStatus: "COMPLETED",
              s3Url: nil
            ),
          ]
        ),
      ],
      [
        ttsRoutineDTO(
          steps: [
            ttsStepDTO(
              ttsStatus: "COMPLETED",
              s3Url: "http://audio.example.com/41.mp3"
            ),
          ]
        ),
      ],
      [ttsRoutineDTO(title: " ")],
      [
        ttsRoutineDTO(
          steps: [ttsStepDTO(content: "\n")]
        ),
      ],
    ]

    for response in invalidResponses {
      let service = DefaultAccountRoutineTTSRemoteService(
        apiClient: RoutineTTSPayloadAPIClient(manifest: response)
      )
      await assertRemoteError(.invalidResponse) {
        _ = try await service.fetchRoutineTTS(
          routineGroupID: 12,
          memberID: 98
        )
      }
    }
  }

  func testDeletionRejectsNonpositiveSwaggerAcknowledgement() async {
    for acknowledgedID in [0, -1] as [Int64] {
      let service = DefaultAccountRoutineTTSRemoteService(
        apiClient: RoutineTTSPayloadAPIClient(
          deletion: RoutineGroupDeleteResponseDTO(
            routineId: acknowledgedID
          )
        )
      )

      await assertRemoteError(.invalidResponse) {
        _ = try await service.deleteRoutineGroup(
          routineGroupID: 12,
          memberID: 98
        )
      }
    }
  }

  func testCancellationAccountChangeAndServerErrorsRemainDistinct()
    async {
    for error in [CancellationError(), APIError.cancelled] as [any Error] {
      let service = DefaultAccountRoutineTTSRemoteService(
        apiClient: RoutineTTSThrowingAPIClient(error: error)
      )

      do {
        _ = try await service.fetchRoutineTTS(
          routineGroupID: 12,
          memberID: 98
        )
        XCTFail("Expected cancellation.")
      } catch is CancellationError {
        continue
      } catch {
        XCTFail("Expected CancellationError, got \(error)")
      }
    }

    let changedAccountService = DefaultAccountRoutineTTSRemoteService(
      apiClient: RoutineTTSThrowingAPIClient(
        error: AccountAuthorizationContextError.memberMismatch
      )
    )
    await assertRemoteError(.accountAuthorizationChanged) {
      _ = try await changedAccountService.fetchRoutineTTS(
        routineGroupID: 12,
        memberID: 98
      )
    }

    let serverError = APIError.server(
      statusCode: 404,
      code: "ROUTINE_GROUP404",
      message: "루틴 그룹을 찾을 수 없습니다."
    )
    let serverErrorService = DefaultAccountRoutineTTSRemoteService(
      apiClient: RoutineTTSThrowingAPIClient(error: serverError)
    )
    do {
      _ = try await serverErrorService.fetchRoutineTTS(
        routineGroupID: 12,
        memberID: 98
      )
      XCTFail("Expected server error.")
    } catch let error as APIError {
      XCTAssertEqual(error, serverError)
    } catch {
      XCTFail("Expected APIError, got \(error)")
    }
  }

  private func assertRemoteError(
    _ expected: AccountRoutineTTSRemoteError,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected).")
    } catch let error as AccountRoutineTTSRemoteError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Expected AccountRoutineTTSRemoteError, got \(error)")
    }
  }

  nonisolated private func makeStubbedService(
    additionalPlugins: [any PluginType & Sendable] = []
  ) -> DefaultAccountRoutineTTSRemoteService {
    let client = DefaultAPIClient(
      tokenProvider: RoutineTTSAccessTokenProvider(),
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
    return DefaultAccountRoutineTTSRemoteService(apiClient: client)
  }
}

nonisolated private func creationGroupRequest()
  -> ServerRoutineGroupCreationRequest {
  ServerRoutineGroupCreationRequest(
    localRoutineID: UUID(),
    title: "아침 루틴",
    description: nil,
    alarmDaysRaw: "MON,TUE,WED,THU,FRI",
    alarmTimeRaw: "07:30",
    weatherNotificationEnabled: true,
    routines: [
      creationRequest(),
    ]
  )
}

nonisolated private func creationRequest(
  localStepID: UUID = UUID(),
  title: String = "물 마시기",
  type: ServerRoutineCreationItemType = .check,
  durationSeconds: Int = 30
) -> ServerRoutineCreationRequest {
  ServerRoutineCreationRequest(
    localStepID: localStepID,
    title: title,
    type: type,
    durationSeconds: durationSeconds
  )
}

nonisolated private func creationDetailDTO(
  routineGroupId: Int64? = 12,
  routines: [RoutineGroupRoutineResponseDTO]? = [
    creationRoutineDTO(),
  ]
) -> RoutineGroupDetailResponseDTO {
  RoutineGroupDetailResponseDTO(
    routineGroupId: routineGroupId,
    title: "아침 루틴",
    description: nil,
    alarmDays: "MON,TUE,WED,THU,FRI",
    alarmTime: "07:30",
    weatherNotificationEnabled: true,
    routines: routines
  )
}

nonisolated private func creationRoutineDTO(
  routineId: Int64? = 31,
  title: String? = "물 마시기",
  type: String? = "CHECK",
  durationSecond: Int? = 30,
  steps: [RoutineGroupStepResponseDTO]? = [
    creationStepDTO(),
  ]
) -> RoutineGroupRoutineResponseDTO {
  RoutineGroupRoutineResponseDTO(
    routineId: routineId,
    title: title,
    type: type,
    durationSecond: durationSecond,
    steps: steps
  )
}

nonisolated private func creationStepDTO(
  stepId: Int64? = 41,
  content: String? = "물 한 잔 준비하기",
  orderIndex: Int? = 0
) -> RoutineGroupStepResponseDTO {
  RoutineGroupStepResponseDTO(
    stepId: stepId,
    content: content,
    orderIndex: orderIndex
  )
}

nonisolated private func ttsRoutineDTO(
  routineId: Int64? = 31,
  title: String? = "물 마시기",
  type: String? = "CHECK",
  steps: [RoutineTTSStepResponseDTO]? = [
    ttsStepDTO(),
  ]
) -> RoutineTTSResponseDTO {
  RoutineTTSResponseDTO(
    routineId: routineId,
    title: title,
    type: type,
    steps: steps
  )
}

nonisolated private func ttsStepDTO(
  stepId: Int64? = 41,
  content: String? = "물 한 잔 준비하기",
  ttsIntro: String? = "물을 한 잔 준비해 볼까요?",
  ttsStatus: String? = "COMPLETED",
  s3Url: String? = "https://audio.example.com/41.mp3"
) -> RoutineTTSStepResponseDTO {
  RoutineTTSStepResponseDTO(
    stepId: stepId,
    content: content,
    ttsIntro: ttsIntro,
    ttsStatus: ttsStatus,
    s3Url: s3Url
  )
}

nonisolated private final class RoutineTTSAccessTokenProvider:
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

nonisolated private final class RoutineTTSRequestCapturePlugin:
  PluginType,
  @unchecked Sendable {
  private let lock = NSLock()
  private var capturedRequests: [URLRequest] = []

  var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return capturedRequests
  }

  func prepare(
    _ request: URLRequest,
    target: TargetType
  ) -> URLRequest {
    lock.lock()
    capturedRequests.append(request)
    lock.unlock()
    return request
  }
}

nonisolated private final class RoutineTTSPayloadAPIClient:
  AccountBoundAPIClient,
  @unchecked Sendable {
  private let creation: RoutineGroupDetailResponseDTO
  private let deletion: RoutineGroupDeleteResponseDTO
  private let manifest: [RoutineTTSResponseDTO]

  init(
    creation: RoutineGroupDetailResponseDTO = creationDetailDTO(),
    deletion: RoutineGroupDeleteResponseDTO =
      RoutineGroupDeleteResponseDTO(routineId: 12),
    manifest: [RoutineTTSResponseDTO] = [ttsRoutineDTO()]
  ) {
    self.creation = creation
    self.deletion = deletion
    self.manifest = manifest
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
    guard memberID == 98 else {
      throw AccountAuthorizationContextError.memberMismatch
    }

    let response: Any
    if let target = target as? RoutineGroupTarget {
      switch target {
      case .create:
        response = creation
      case .delete:
        response = deletion
      case .list, .detail:
        throw APIError.invalidRequest(
          "Unexpected routine-group read request."
        )
      }
    } else if target is RoutineTTSTarget {
      response = manifest
    } else {
      throw APIError.invalidRequest("Unexpected target.")
    }

    guard let payload = response as? Payload else {
      throw APIError.decoding("Unexpected routine-TTS payload type.")
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

nonisolated private final class RoutineTTSCallCountingAPIClient:
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

nonisolated private final class RoutineTTSThrowingAPIClient:
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
