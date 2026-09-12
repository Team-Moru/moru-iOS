//
//  RoutineTTSBindingValidatorTests.swift
//  MoruTests
//

import SwiftData
import XCTest
@testable import Moru

/// 준비해 둔 오디오가 지금도 그 루틴의 것인지 판단하는 규칙.
///
/// 예전에는 이 규칙이 `RoutineTTSWarmupCoordinator` 안에 있어서, 시험하려면
/// 원격 서비스·오디오 캐시·다운로더·음성 선택 저장소까지 모두 세워야 했다.
/// 떼어낸 뒤로는 동기화 저장소 하나만 있으면 된다.
///
/// 여기서 지키는 것은 하나다 — **남의 루틴 음성이 재생되면 안 된다.**
@MainActor
final class RoutineTTSBindingValidatorTests: XCTestCase {
  private let memberID: Int64 = 7
  private let groupRemoteID: Int64 = 41
  private let routineRemoteID: Int64 = 51

  func testValidBindingPairIsAccepted() throws {
    let scene = try makeScene()

    XCTAssertEqual(
      scene.validator.validateCurrentBinding(
        routineGroupLocalID: scene.groupLocalID,
        routineLocalID: scene.routineLocalID,
        expectedGroupRemoteID: groupRemoteID,
        expectedRoutineRemoteID: routineRemoteID,
        identity: scene.identity
      ),
      .valid
    )
  }

  /// 서버가 루틴을 다시 만들어 remote ID가 달라졌다면, 캐시된 오디오는 옛
  /// 루틴의 것이다. 틀어 주면 사용자는 지운 루틴의 안내를 듣는다.
  func testRemoteIDChangeInvalidatesThePreparedPlan() throws {
    let scene = try makeScene()

    XCTAssertEqual(
      scene.validator.validateCurrentBinding(
        routineGroupLocalID: scene.groupLocalID,
        routineLocalID: scene.routineLocalID,
        expectedGroupRemoteID: groupRemoteID,
        expectedRoutineRemoteID: routineRemoteID + 1,
        identity: scene.identity
      ),
      .invalid
    )
  }

  /// 다른 계정으로 갈아탄 뒤에는 이전 계정의 바인딩이 보이면 안 된다.
  func testAnotherAccountSeesNoBinding() throws {
    let scene = try makeScene()
    let otherAccount = AccountSessionIdentity(
      memberID: memberID + 1,
      sessionID: UUID()
    )

    XCTAssertEqual(
      scene.validator.validateCurrentBinding(
        routineGroupLocalID: scene.groupLocalID,
        routineLocalID: scene.routineLocalID,
        expectedGroupRemoteID: groupRemoteID,
        expectedRoutineRemoteID: routineRemoteID,
        identity: otherAccount
      ),
      .invalid
    )
  }

  func testUnboundRoutineIsInvalid() throws {
    let scene = try makeScene()

    XCTAssertEqual(
      scene.validator.validateCurrentBinding(
        routineGroupLocalID: UUID(),
        routineLocalID: UUID(),
        expectedGroupRemoteID: groupRemoteID,
        expectedRoutineRemoteID: routineRemoteID,
        identity: scene.identity
      ),
      .invalid
    )
  }

  /// 바인딩이 이미 있으면 서버가 만든 안내를 기다려야 한다. 로컬 루틴으로
  /// 착각하면 번들 음성을 틀어 버린다.
  func testBoundRoutineReportsServerSyncIntent() throws {
    let scene = try makeScene()

    XCTAssertTrue(
      try scene.validator.hasServerSyncIntent(
        memberID: memberID,
        routineGroupLocalID: scene.groupLocalID,
        routineLocalID: scene.routineLocalID
      )
    )
    XCTAssertFalse(
      try scene.validator.hasServerSyncIntent(
        memberID: memberID,
        routineGroupLocalID: UUID(),
        routineLocalID: UUID()
      )
    )
  }

  /// `blocked`만 스스로 풀리지 않는 상태다. 나머지는 첫 큐를 기다리는 동안
  /// 서버 바인딩을 얻을 수 있으므로 기다릴 값어치가 있다.
  func testOnlyBlockedIsTreatedAsANonPendingDelivery() {
    let pending: [RoutineSyncMutationState] = [
      .waitingForServerContract, .queued, .attempting, .needsReconciliation,
    ]

    for state in pending {
      XCTAssertTrue(
        RoutineTTSBindingValidator.isDeliveryPending(state),
        "\(state)"
      )
    }
    XCTAssertFalse(RoutineTTSBindingValidator.isDeliveryPending(.blocked))
  }

  // MARK: - 픽스처

  private struct Scene {
    let validator: RoutineTTSBindingValidator
    let identity: AccountSessionIdentity
    let groupLocalID: UUID
    let routineLocalID: UUID
  }

  private func makeScene() throws -> Scene {
    let groupLocalID = UUID()
    let routineLocalID = UUID()
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let bindings = SwiftDataRoutineSyncRepository(modelContainer: container)

    _ = try bindings.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routineGroup,
          localEntityID: groupLocalID,
          remoteID: groupRemoteID
        ),
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: routineLocalID,
          remoteID: routineRemoteID,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupLocalID
        ),
      ],
      memberID: memberID,
      at: .distantPast
    )

    return Scene(
      validator: RoutineTTSBindingValidator(
        bindingRepository: bindings,
        serverNamespace: .production
      ),
      identity: AccountSessionIdentity(memberID: memberID, sessionID: UUID()),
      groupLocalID: groupLocalID,
      routineLocalID: routineLocalID
    )
  }
}
