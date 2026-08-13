//
//  RoutineSyncRuntimeCoordinatorTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

final class RoutineSyncRuntimeCoordinatorTests: XCTestCase {
  @MainActor
  func testWakeRunsOnlyForActiveSceneAndCurrentSignedInMember() async {
    let sender = ScriptedRoutineSyncSender(results: [.idle])
    let provider = RuntimeSessionIdentityProvider(identity: nil)
    let coordinator = RoutineSyncRuntimeCoordinator(
      sender: sender,
      sessionIdentityProvider: provider
    )

    coordinator.wake()
    await yieldToRuntime()
    XCTAssertEqual(sender.callCount, 0)
    XCTAssertEqual(coordinator.lastStopReason, .inactive)

    coordinator.setSceneActive(true)
    await yieldToRuntime()
    XCTAssertEqual(sender.callCount, 0)
    XCTAssertEqual(coordinator.lastStopReason, .signedOut)

    let identity = AccountSessionIdentity(memberID: 71, sessionID: UUID())
    provider.identity = identity
    coordinator.accountSessionDidChange()
    await waitUntilStopped(coordinator)

    XCTAssertEqual(sender.memberIDs, [identity.memberID])
    XCTAssertEqual(coordinator.lastStopReason, .idle)
  }

  @MainActor
  func testRelayWakeCoalescesIntoOneSerialDrainUntilIdle() async {
    let firstID = UUID()
    let secondID = UUID()
    let sender = ScriptedRoutineSyncSender(
      results: [
        .completed(mutationID: firstID),
        .completed(mutationID: secondID),
        .idle,
      ],
      yieldsDuringSend: true
    )
    let provider = RuntimeSessionIdentityProvider(
      identity: AccountSessionIdentity(memberID: 7, sessionID: UUID())
    )
    let relay = RoutineSyncWakeupRelay()
    let coordinator = RoutineSyncRuntimeCoordinator(
      sender: sender,
      sessionIdentityProvider: provider,
      wakeupRelay: relay,
      isSceneActive: true
    )

    relay.wake()
    relay.wake()
    relay.wake()
    await waitUntilStopped(coordinator)

    XCTAssertEqual(sender.callCount, 3)
    XCTAssertEqual(sender.maximumConcurrentCalls, 1)
    XCTAssertEqual(coordinator.lastStopReason, .idle)
  }

  @MainActor
  func testRetrySleepsUntilPersistedNextAttemptDateThenResumes() async {
    let start = Date(timeIntervalSince1970: 10_000)
    let retryAt = start.addingTimeInterval(8)
    let mutationID = UUID()
    let sender = ScriptedRoutineSyncSender(
      results: [
        .retryScheduled(
          mutationID: mutationID,
          nextAttemptAt: retryAt
        ),
        .idle,
      ]
    )
    let scheduler = ImmediateRoutineSyncRuntimeScheduler(now: start)
    let provider = RuntimeSessionIdentityProvider(
      identity: AccountSessionIdentity(memberID: 9, sessionID: UUID())
    )
    let coordinator = RoutineSyncRuntimeCoordinator(
      sender: sender,
      sessionIdentityProvider: provider,
      scheduler: scheduler,
      isSceneActive: true
    )

    coordinator.wake()
    await waitUntilStopped(coordinator)

    XCTAssertEqual(scheduler.sleepDates, [retryAt])
    XCTAssertEqual(sender.sendDates, [start, retryAt])
    XCTAssertEqual(sender.maximumConcurrentCalls, 1)
  }

  @MainActor
  func testRetryWithoutDateUsesBoundedFallbackDelay() async {
    let start = Date(timeIntervalSince1970: 20_000)
    let sender = ScriptedRoutineSyncSender(
      results: [
        .retryScheduled(mutationID: UUID(), nextAttemptAt: nil),
        .idle,
      ]
    )
    let scheduler = ImmediateRoutineSyncRuntimeScheduler(now: start)
    let provider = RuntimeSessionIdentityProvider(
      identity: AccountSessionIdentity(memberID: 11, sessionID: UUID())
    )
    let coordinator = RoutineSyncRuntimeCoordinator(
      sender: sender,
      sessionIdentityProvider: provider,
      scheduler: scheduler,
      isSceneActive: true,
      unscheduledRetryDelay: 2
    )

    coordinator.wake()
    await waitUntilStopped(coordinator)

    XCTAssertEqual(
      scheduler.sleepDates,
      [start.addingTimeInterval(2)]
    )
  }

  @MainActor
  func testBlockedAndStaleResultsStopWithoutAnotherSend() async {
    let identity = AccountSessionIdentity(memberID: 13, sessionID: UUID())
    let provider = RuntimeSessionIdentityProvider(identity: identity)
    let blockedSender = ScriptedRoutineSyncSender(
      results: [
        .blocked(
          mutationID: UUID(),
          reason: .idempotencyPayloadConflict
        ),
        .idle,
      ]
    )
    let blockedCoordinator = RoutineSyncRuntimeCoordinator(
      sender: blockedSender,
      sessionIdentityProvider: provider,
      isSceneActive: true
    )

    blockedCoordinator.wake()
    await waitUntilStopped(blockedCoordinator)
    XCTAssertEqual(blockedSender.callCount, 1)
    XCTAssertEqual(
      blockedCoordinator.lastStopReason,
      .blocked(.idempotencyPayloadConflict)
    )

    let staleSender = ScriptedRoutineSyncSender(
      results: [.staleSession(mutationID: UUID()), .idle]
    )
    let staleCoordinator = RoutineSyncRuntimeCoordinator(
      sender: staleSender,
      sessionIdentityProvider: provider,
      isSceneActive: true
    )

    staleCoordinator.wake()
    await waitUntilStopped(staleCoordinator)
    XCTAssertEqual(staleSender.callCount, 1)
    XCTAssertEqual(staleCoordinator.lastStopReason, .staleSession)
  }

  @MainActor
  private func waitUntilStopped(
    _ coordinator: RoutineSyncRuntimeCoordinator,
    iterations: Int = 100
  ) async {
    for _ in 0..<iterations {
      if !coordinator.isDraining { return }
      await Task.yield()
    }
    XCTFail("Routine sync runtime did not stop.")
  }

  @MainActor
  private func yieldToRuntime(iterations: Int = 4) async {
    for _ in 0..<iterations {
      await Task.yield()
    }
  }
}

@MainActor
private final class ScriptedRoutineSyncSender: RoutineSyncSending {
  private var results: [RoutineSyncSendResult]
  private let yieldsDuringSend: Bool
  private var activeCalls = 0

  private(set) var callCount = 0
  private(set) var maximumConcurrentCalls = 0
  private(set) var memberIDs: [Int64] = []
  private(set) var sendDates: [Date] = []

  init(
    results: [RoutineSyncSendResult],
    yieldsDuringSend: Bool = false
  ) {
    self.results = results
    self.yieldsDuringSend = yieldsDuringSend
  }

  func sendNext(
    memberID: Int64,
    at date: Date
  ) async throws -> RoutineSyncSendResult {
    activeCalls += 1
    maximumConcurrentCalls = max(maximumConcurrentCalls, activeCalls)
    defer { activeCalls -= 1 }

    callCount += 1
    memberIDs.append(memberID)
    sendDates.append(date)
    if yieldsDuringSend {
      await Task.yield()
    }
    guard !results.isEmpty else { return .idle }
    return results.removeFirst()
  }
}

@MainActor
private final class RuntimeSessionIdentityProvider:
  CurrentAccountSessionIdentityProviding {
  var identity: AccountSessionIdentity?

  init(identity: AccountSessionIdentity?) {
    self.identity = identity
  }

  var currentAccountSessionIdentity: AccountSessionIdentity? { identity }
}

@MainActor
private final class ImmediateRoutineSyncRuntimeScheduler:
  RoutineSyncRuntimeScheduling {
  var now: Date
  private(set) var sleepDates: [Date] = []

  init(now: Date) {
    self.now = now
  }

  func sleep(until date: Date) async throws {
    sleepDates.append(date)
    now = date
  }
}
