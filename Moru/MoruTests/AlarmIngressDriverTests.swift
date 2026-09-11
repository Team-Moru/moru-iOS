//
//  AlarmIngressDriverTests.swift
//  MoruTests
//

import Foundation
import XCTest
@testable import Moru

/// 알람 진입 규칙을 View 밖에서 직접 검증한다. 예전에는 이 로직이 AppRouter의
/// private 메서드였고, 라우터를 View로 세우는 테스트가 없어 간접적으로만 덮였다.
@MainActor
final class AlarmIngressDriverTests: XCTestCase {
  func testScheduledLaunchStopsTheAlarmOnlyAfterThePlayerIsAdmitted() async {
    let routineID = UUID()
    let context = makeContext(routineID: routineID, launchTarget: .scheduledRoutine)
    let handler = AlarmRuntimeHandlerSpy(resolution: .route(context))
    let coordinator = AppNavigationCoordinator()
    let monitor = ScheduledAlarmStopMonitor()
    let driver = AlarmIngressDriver(
      alarmRuntimeHandler: handler,
      coordinator: coordinator,
      alarmStopMonitor: monitor
    )

    await driver.handle(context.ingress)

    // 표시가 승인됐으므로 정지가 시작된다.
    XCTAssertNotNil(coordinator.presentation)
    await handler.waitForStopAttempt()
    XCTAssertEqual(handler.stopCallCount, 1)
  }

  func testBusyPresentationDefersWithoutStoppingTheAlarm() async {
    let firstContext = makeContext(
      routineID: UUID(),
      launchTarget: .scheduledRoutine
    )
    let secondContext = makeContext(
      routineID: UUID(),
      launchTarget: .scheduledRoutine
    )
    let handler = AlarmRuntimeHandlerSpy(resolution: .route(firstContext))
    let coordinator = AppNavigationCoordinator()
    let driver = AlarmIngressDriver(
      alarmRuntimeHandler: handler,
      coordinator: coordinator,
      alarmStopMonitor: ScheduledAlarmStopMonitor()
    )

    await driver.handle(firstContext.ingress)
    await handler.waitForStopAttempt()
    let stopsAfterFirst = handler.stopCallCount

    handler.resolution = .route(secondContext)
    await driver.handle(secondContext.ingress)

    // 이미 플레이어가 떠 있으면 두 번째 알람은 미뤄지고 정지하지 않는다.
    // 여기서 끄면 부활 경로가 다시 들어올 알람을 미리 꺼 버린다.
    XCTAssertEqual(handler.stopCallCount, stopsAfterFirst)
  }

  func testRetryDeferredIngressReportsWhenThereIsNothingToRetry() async {
    let driver = AlarmIngressDriver(
      alarmRuntimeHandler: AlarmRuntimeHandlerSpy(resolution: .ignored(.stale)),
      coordinator: AppNavigationCoordinator(),
      alarmStopMonitor: ScheduledAlarmStopMonitor()
    )

    let didHandle = await driver.retryDeferredIngress()

    XCTAssertFalse(didHandle)
  }

  func testMissingRuntimeHandlerReleasesTheEnvelopeInsteadOfConsumingIt() async {
    let context = makeContext(routineID: UUID(), launchTarget: .scheduledRoutine)
    let coordinator = AppNavigationCoordinator()
    let driver = AlarmIngressDriver(
      alarmRuntimeHandler: nil,
      coordinator: coordinator,
      alarmStopMonitor: ScheduledAlarmStopMonitor()
    )

    await driver.handle(context.ingress)

    XCTAssertNil(coordinator.presentation)
  }

  func testRestoringAccountDefersIngressUntilRestorationFinishes() async {
    let handler = AlarmRuntimeHandlerSpy(resolution: .ignored(.stale))
    let driver = AlarmIngressDriver(
      alarmRuntimeHandler: handler,
      coordinator: AppNavigationCoordinator(),
      alarmStopMonitor: ScheduledAlarmStopMonitor()
    )

    await driver.consumePendingIngress(
      sessionPhase: SessionStore.Phase.ready,
      accountState: AccountSessionState.restoring
    )

    XCTAssertEqual(handler.resolveCallCount, 0)
  }

  func testStopRetryWithoutAFailedStopDoesNothing() {
    let handler = AlarmRuntimeHandlerSpy(resolution: .ignored(.stale))
    let driver = AlarmIngressDriver(
      alarmRuntimeHandler: handler,
      coordinator: AppNavigationCoordinator(),
      alarmStopMonitor: ScheduledAlarmStopMonitor()
    )

    driver.retryStop()

    XCTAssertEqual(handler.stopCallCount, 0)
  }
}

@MainActor
private final class AlarmRuntimeHandlerSpy: AlarmRuntimeHandling {
  var resolution: AlarmIngressResolution
  private(set) var resolveCallCount = 0
  private(set) var stopCallCount = 0

  init(resolution: AlarmIngressResolution) {
    self.resolution = resolution
  }

  func resolve(_ envelope: AlarmIngressEnvelope) async -> AlarmIngressResolution {
    resolveCallCount += 1
    return resolution
  }

  func stopAlarm(for context: AlarmRingContext) async throws {
    stopCallCount += 1
  }

  func snooze(
    context: AlarmRingContext,
    minutes: Int
  ) async throws -> SnoozedAlarmRecord {
    throw AlarmRuntimeError.routeNoLongerAvailable
  }

  /// 정지는 소유하지 않은 Task에서 일어난다. 카운트가 오를 때까지만 양보한다.
  func waitForStopAttempt() async {
    for _ in 0..<100 where stopCallCount == 0 {
      await Task.yield()
    }
  }
}

private func makeContext(
  routineID: UUID,
  launchTarget: AlarmIngressLaunchTarget
) -> AlarmRingContext {
  AlarmRingContext(
    ingress: AlarmIngressEnvelope(
      alarmID: UUID(),
      routineID: routineID,
      scheduleID: UUID(),
      kind: .recurring,
      fireDate: Date(),
      nonce: UUID(),
      launchTarget: launchTarget
    ),
    routineName: "활력 루틴",
    routineMinutes: 10
  )
}
