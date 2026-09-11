//
//  ScheduledAlarmStopMonitorTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

@MainActor
final class ScheduledAlarmStopMonitorTests: XCTestCase {
  func testPolicyStopsOnlyAfterPresentationIsAdmitted() {
    let token = UUID()

    XCTAssertEqual(ScheduledAlarmStopPolicy.action(for: .deferredBusy), .defer)
    XCTAssertEqual(
      ScheduledAlarmStopPolicy.action(for: .presented(token)),
      .completeAndStop(presentationToken: token)
    )
    XCTAssertEqual(
      ScheduledAlarmStopPolicy.action(for: .alreadyPresented(token)),
      .completeAndStop(presentationToken: token)
    )
  }

  func testFirstAttemptShowsNoBannerAndFailureShowsItForTheSamePresentationOnly() {
    let monitor = ScheduledAlarmStopMonitor()
    let token = UUID()
    let context = makeContext()

    monitor.begin(context: context, presentationToken: token)
    XCTAssertEqual(monitor.phase, .stopping)
    XCTAssertFalse(monitor.showsRetryBanner(for: token))

    monitor.markFailed()
    XCTAssertEqual(monitor.phase, .failed)
    XCTAssertTrue(monitor.showsRetryBanner(for: token))
    XCTAssertFalse(monitor.showsRetryBanner(for: UUID()))
    XCTAssertFalse(monitor.isRetrying)
  }

  func testRetryKeepsTheBannerLocksTheButtonAndClearsOnSuccess() {
    let monitor = ScheduledAlarmStopMonitor()
    let token = UUID()
    let context = makeContext()

    XCTAssertNil(monitor.beginRetry(), "실패 전에는 재시도할 것이 없다.")

    monitor.begin(context: context, presentationToken: token)
    monitor.markFailed()

    XCTAssertEqual(monitor.beginRetry(), context)
    XCTAssertEqual(monitor.phase, .retrying)
    XCTAssertTrue(monitor.showsRetryBanner(for: token))
    XCTAssertTrue(monitor.isRetrying)
    XCTAssertNil(monitor.beginRetry(), "재시도 중에는 중복 재시도를 받지 않는다.")

    monitor.markFailed()
    XCTAssertEqual(monitor.phase, .failed)
    XCTAssertEqual(monitor.beginRetry(), context)

    monitor.markStopped()
    XCTAssertEqual(monitor.phase, .idle)
    XCTAssertFalse(monitor.showsRetryBanner(for: token))
    XCTAssertNil(monitor.context)
  }

  func testDismissalClearsAFailedStopSoTheNextPlayerStartsClean() {
    let monitor = ScheduledAlarmStopMonitor()
    let token = UUID()

    monitor.begin(context: makeContext(), presentationToken: token)
    monitor.markFailed()
    monitor.clear()

    XCTAssertEqual(monitor.phase, .idle)
    XCTAssertFalse(monitor.showsRetryBanner(for: token))
    XCTAssertNil(monitor.beginRetry())
  }

  func testFailureWithoutAnAttemptIsIgnored() {
    let monitor = ScheduledAlarmStopMonitor()
    monitor.markFailed()
    XCTAssertEqual(monitor.phase, .idle)
  }

  private func makeContext() -> AlarmRingContext {
    AlarmRingContext(
      ingress: AlarmIngressEnvelope(
        alarmID: UUID(),
        routineID: UUID(),
        scheduleID: UUID(),
        kind: .recurring,
        fireDate: Date(),
        nonce: UUID(),
        launchTarget: .scheduledRoutine
      ),
      routineName: "아침 루틴",
      routineMinutes: 10
    )
  }
}
