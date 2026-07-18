//
//  AppLaunchCoordinatorTests.swift
//  MoruTests
//
//  Created by Codex on 7/18/26.
//

import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Moru

final class AppLaunchCoordinatorTests: XCTestCase {
  @MainActor
  func testLaunchStatusRemainsHiddenAt499MillisecondsAndAppearsAt500Milliseconds() async {
    let factory = ControlledContainerFactory()
    let clock = ControlledLaunchClock()
    let coordinator = AppLaunchCoordinator(modelContainerFactory: factory, clock: clock)

    coordinator.start()
    await waitForFactoryRequests(1, factory: factory)
    await waitForClockSleepers(2, clock: clock)

    await clock.advance(by: .milliseconds(499))
    await Task.yield()
    XCTAssertFalse(coordinator.showsLaunchStatus)

    await clock.advance(by: .milliseconds(1))
    await Task.yield()
    XCTAssertTrue(coordinator.showsLaunchStatus)
  }

  @MainActor
  func testRepeatedStartCannotCreateASecondLaunchOwner() async {
    let factory = ControlledContainerFactory()
    let coordinator = AppLaunchCoordinator(modelContainerFactory: factory)

    coordinator.start()
    coordinator.start()
    await waitForFactoryRequests(1, factory: factory)
    await Task.yield()

    let requestCount = await factory.requestCount()
    XCTAssertEqual(requestCount, 1)
  }

  @MainActor
  func testLaunchTimesOutOnlyAtEightSeconds() async {
    let factory = ControlledContainerFactory()
    let clock = ControlledLaunchClock()
    let coordinator = AppLaunchCoordinator(modelContainerFactory: factory, clock: clock)

    coordinator.start()
    await waitForClockSleepers(2, clock: clock)

    await clock.advance(by: .milliseconds(7_999))
    await Task.yield()
    XCTAssertTrue(coordinator.showsLaunchStatus)
    assertConstructing(coordinator)

    await clock.advance(by: .milliseconds(1))
    await waitUntil("The eighth second should time out construction.") {
      if case .bootstrapFailed(let failure) = coordinator.phase {
        failure.kind == .timedOut
      } else {
        false
      }
    }
  }

  @MainActor
  func testSessionLoadingTimeoutRejectsLateSnapshot() async throws {
    let container = try SendableModelContainer.inMemoryForTesting()
    let factory = ControlledContainerFactory()
    let loader = ControlledSnapshotLoader()
    let clock = ControlledLaunchClock()
    let coordinator = AppLaunchCoordinator(
      modelContainerFactory: factory,
      loaderFactory: FixedLoaderFactory(loader: loader),
      clock: clock
    )

    coordinator.start()
    await waitForFactoryRequests(1, factory: factory)
    await waitForClockSleepers(2, clock: clock)
    let didConstruct = await factory.succeedNext(container)
    XCTAssertTrue(didConstruct)
    await waitForLoaderRequests(1, loader: loader)
    await waitForClockSleepers(4, clock: clock)

    await clock.advance(by: .seconds(8))
    let timedOutPending = await sessionFailurePending(from: coordinator)
    let pending = try XCTUnwrap(timedOutPending)
    XCTAssertEqual(coordinator.lastFailure?.kind, .timedOut)

    let didFinishLate = await loader.succeedNext(readySnapshot())
    XCTAssertTrue(didFinishLate)
    await Task.yield()
    await Task.yield()

    guard case .sessionFailed(let activePending, let failure) = coordinator.phase else {
      XCTFail("A late snapshot must not leave the session-failed phase.")
      return
    }
    XCTAssertTrue(activePending === pending)
    XCTAssertEqual(failure.kind, .timedOut)
    XCTAssertFalse(pending.wasTransferred)
  }

  @MainActor
  func testCancelledStatusTimerCannotChangeFinishedAttempt() async {
    let factory = ControlledContainerFactory()
    let clock = ControlledLaunchClock()
    let coordinator = AppLaunchCoordinator(modelContainerFactory: factory, clock: clock)

    coordinator.start()
    await waitForFactoryRequests(1, factory: factory)
    await waitForClockSleepers(2, clock: clock)
    let didFail = await factory.failNext()
    XCTAssertTrue(didFail)
    await waitUntil("Construction failure should finish the attempt.") {
      if case .bootstrapFailed = coordinator.phase {
        true
      } else {
        false
      }
    }
    XCTAssertTrue(
      coordinator.lastFailure?.diagnosticDescription?.contains("expected") == true
    )

    await clock.advance(by: .milliseconds(500))
    await Task.yield()
    XCTAssertFalse(coordinator.showsLaunchStatus)
  }

  @MainActor
  func testClockFailureFailsClosedInsteadOfLeavingLaunchPending() async {
    let factory = ControlledContainerFactory()
    let clock = ControlledLaunchClock()
    let coordinator = AppLaunchCoordinator(modelContainerFactory: factory, clock: clock)

    coordinator.start()
    await waitForClockSleepers(2, clock: clock)
    await clock.failAll()

    await waitUntil("Clock failure should fail the active launch attempt.") {
      if case .bootstrapFailed(let failure) = coordinator.phase {
        failure.kind == .timedOut
      } else {
        false
      }
    }
  }

  @MainActor
  func testLaunchStatusRendersExactNativeCopy() throws {
    XCTAssertEqual(LaunchStatusView.message, "루틴을 준비하고 있어요")
    let bounds = CGRect(x: 0, y: 0, width: 393, height: 852)
    let windowScene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    )
    let hostingController = UIHostingController(rootView: LaunchStatusView())
    let window = UIWindow(windowScene: windowScene)
    window.frame = bounds
    window.rootViewController = hostingController
    window.makeKeyAndVisible()
    hostingController.view.frame = bounds
    hostingController.view.layoutIfNeeded()

    let renderer = UIGraphicsImageRenderer(bounds: bounds)
    let image = renderer.image { _ in
      hostingController.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
    }
    window.isHidden = true

    let pngData = try XCTUnwrap(image.pngData())
    try pngData.write(
      to: URL(fileURLWithPath: "/tmp/moru-g002-launch-status.png"),
      options: .atomic
    )
    XCTAssertGreaterThan(pngData.count, 1_000)
  }

  @MainActor
  func testConstructionRetryUsesANewLaunchGeneration() async throws {
    let factory = ControlledContainerFactory()
    let coordinator = AppLaunchCoordinator(modelContainerFactory: factory)

    coordinator.start()
    await waitForFactoryRequests(1, factory: factory)
    let firstToken = try XCTUnwrap(coordinator.activeAttemptToken)
    let didFail = await factory.failNext()
    XCTAssertTrue(didFail)
    await waitUntil("Construction failure should be reported.") {
      if case .bootstrapFailed = coordinator.phase {
        true
      } else {
        false
      }
    }

    coordinator.retry()
    await waitForFactoryRequests(2, factory: factory)
    let secondToken = try XCTUnwrap(coordinator.activeAttemptToken)
    XCTAssertGreaterThan(secondToken.launchGeneration, firstToken.launchGeneration)
    XCTAssertNotEqual(secondToken, firstToken)
  }

  @MainActor
  func testSessionRetryKeepsPendingResourcesAndUsesANewAttempt() async throws {
    let container = try SendableModelContainer.inMemoryForTesting()
    let factory = StableContainerFactory(container: container)
    let loader = ControlledSnapshotLoader()
    let coordinator = AppLaunchCoordinator(
      modelContainerFactory: factory,
      loaderFactory: FixedLoaderFactory(loader: loader)
    )

    coordinator.start()
    await waitForLoaderRequests(1, loader: loader)
    let firstToken = try XCTUnwrap(coordinator.activeAttemptToken)
    let didFail = await loader.failNext()
    XCTAssertTrue(didFail)
    let failedPending = await sessionFailurePending(from: coordinator)
    let pending = try XCTUnwrap(failedPending)
    XCTAssertTrue(
      coordinator.lastFailure?.diagnosticDescription?.contains("expected") == true
    )

    coordinator.retry()
    await waitForLoaderRequests(2, loader: loader)
    let secondToken = try XCTUnwrap(coordinator.activeAttemptToken)
    assertLoading(coordinator, pending: pending)
    let factoryRequestCount = await factory.requestCount()
    XCTAssertEqual(factoryRequestCount, 1)
    XCTAssertEqual(secondToken.launchGeneration, firstToken.launchGeneration)
    XCTAssertGreaterThan(secondToken.attemptNumber, firstToken.attemptNumber)
  }

  @MainActor
  func testFourthSessionFailureRequiresRecoveryAndDisposesCandidate() async throws {
    let container = try SendableModelContainer.inMemoryForTesting()
    let factory = StableContainerFactory(container: container)
    let loader = ControlledSnapshotLoader()
    let coordinator = AppLaunchCoordinator(
      modelContainerFactory: factory,
      loaderFactory: FixedLoaderFactory(loader: loader)
    )

    coordinator.start()
    await waitForLoaderRequests(1, loader: loader)
    let didFail = await loader.failNext()
    XCTAssertTrue(didFail)
    let failedPending = await sessionFailurePending(from: coordinator)
    let pending = try XCTUnwrap(failedPending)

    for requestCount in 2...4 {
      coordinator.retry()
      await waitForLoaderRequests(requestCount, loader: loader)
      let didFail = await loader.failNext()
      XCTAssertTrue(didFail)
      if requestCount < 4 {
        let failedPending = await sessionFailurePending(from: coordinator)
        _ = try XCTUnwrap(failedPending)
      }
    }

    await waitUntil("The initial failure plus three retries should require recovery.") {
      if case .recoveryRequired = coordinator.phase {
        true
      } else {
        false
      }
    }
    XCTAssertTrue(pending.wasDisposed)
    XCTAssertFalse(pending.wasTransferred)
  }

  @MainActor
  func testFourthBootstrapFailureRequiresRecoveryAfterThreeExplicitRetries() async {
    let factory = ControlledContainerFactory()
    let coordinator = AppLaunchCoordinator(modelContainerFactory: factory)

    coordinator.start()
    await waitForFactoryRequests(1, factory: factory)
    let didFail = await factory.failNext()
    XCTAssertTrue(didFail)

    for requestCount in 2...4 {
      await waitUntil("Bootstrap failure should permit an explicit retry.") {
        if case .bootstrapFailed = coordinator.phase {
          true
        } else {
          false
        }
      }
      coordinator.retry()
      await waitForFactoryRequests(requestCount, factory: factory)
      let didFail = await factory.failNext()
      XCTAssertTrue(didFail)
    }

    await waitUntil("The fourth bootstrap failure should require recovery.") {
      if case .recoveryRequired = coordinator.phase {
        true
      } else {
        false
      }
    }
  }

  @MainActor
  func testLateConstructionCandidateCannotReplaceTimedOutFailure() async throws {
    let factory = ControlledContainerFactory()
    let clock = ControlledLaunchClock()
    let coordinator = AppLaunchCoordinator(modelContainerFactory: factory, clock: clock)

    coordinator.start()
    await waitForFactoryRequests(1, factory: factory)
    await waitForClockSleepers(2, clock: clock)
    await clock.advance(by: .seconds(8))
    await waitUntil("Construction should time out.") {
      if case .bootstrapFailed(let failure) = coordinator.phase {
        failure.kind == .timedOut
      } else {
        false
      }
    }

    let didSucceed = await factory.succeedNext(try SendableModelContainer.inMemoryForTesting())
    XCTAssertTrue(didSucceed)
    await Task.yield()
    await Task.yield()
    if case .bootstrapFailed(let failure) = coordinator.phase, failure.kind == .timedOut {
      return
    }
    XCTFail("A late construction candidate must not mutate the timed-out phase.")
  }

  @MainActor
  func testReadyInstallationTransfersPendingResourcesExactlyOnce() async throws {
    let container = try SendableModelContainer.inMemoryForTesting()
    let factory = StableContainerFactory(container: container)
    let loader = ControlledSnapshotLoader()
    let coordinator = AppLaunchCoordinator(
      modelContainerFactory: factory,
      loaderFactory: FixedLoaderFactory(loader: loader)
    )

    coordinator.start()
    await waitForLoaderRequests(1, loader: loader)
    let pending = try XCTUnwrap(loadingPending(from: coordinator))
    let didSucceed = await loader.succeedNext(readySnapshot())
    XCTAssertTrue(didSucceed)
    await waitUntil("A valid snapshot should install the ready graph.") {
      if case .ready = coordinator.phase {
        true
      } else {
        false
      }
    }
    guard case .ready(let launchedApp) = coordinator.phase else {
      XCTFail("Ready installation should retain the launched app.")
      return
    }
    XCTAssertEqual(launchedApp.sessionStore.phase, .ready)

    XCTAssertTrue(pending.wasTransferred)
    XCTAssertFalse(pending.wasDisposed)
    XCTAssertEqual(pending.transferCount, 1)
  }

  @MainActor
  func testReloadSourcesUseFullIdentityAndSerializeDifferentCases() async throws {
    let container = try SendableModelContainer.inMemoryForTesting()
    let factory = StableContainerFactory(container: container)
    let loader = ControlledSnapshotLoader()
    let coordinator = AppLaunchCoordinator(
      modelContainerFactory: factory,
      loaderFactory: FixedLoaderFactory(loader: loader)
    )

    coordinator.start()
    await waitForLoaderRequests(1, loader: loader)
    let didInstall = await loader.succeedNext(readySnapshot())
    XCTAssertTrue(didInstall)
    await waitUntil("Initial snapshot should install the app.") {
      if case .ready = coordinator.phase {
        true
      } else {
        false
      }
    }

    let token = UUID()
    let routineMutation = SessionReloadSource.routineMutation(token)
    coordinator.requestSessionReload(source: routineMutation)
    coordinator.requestSessionReload(source: routineMutation)
    coordinator.requestSessionReload(source: .trialDismissal(token))

    await waitForLoaderRequests(2, loader: loader)
    let didCompleteRoutineReload = await loader.succeedNext(readySnapshot())
    XCTAssertTrue(didCompleteRoutineReload)
    await waitForLoaderRequests(3, loader: loader)
    let didCompleteTrialReload = await loader.succeedNext(readySnapshot())
    XCTAssertTrue(didCompleteTrialReload)
    await Task.yield()

    let loaderRequestCount = await loader.requestCount()
    XCTAssertEqual(loaderRequestCount, 3)
  }

  @MainActor
  func testFailedReloadRetriesExactSourceAndCompletesDedupeOnlyAfterSuccess() async throws {
    let container = try SendableModelContainer.inMemoryForTesting()
    let loader = ControlledSnapshotLoader()
    let coordinator = AppLaunchCoordinator(
      modelContainerFactory: StableContainerFactory(container: container),
      loaderFactory: FixedLoaderFactory(loader: loader)
    )

    coordinator.start()
    await waitForLoaderRequests(1, loader: loader)
    let didInstall = await loader.succeedNext(readySnapshot())
    XCTAssertTrue(didInstall)
    await waitUntil("Initial snapshot should install the app.") {
      if case .ready = coordinator.phase {
        true
      } else {
        false
      }
    }

    guard case .ready(let launchedApp) = coordinator.phase else {
      XCTFail("Expected a launched app.")
      return
    }

    let source = SessionReloadSource.trialDismissal(UUID())
    coordinator.requestSessionReload(source: source)
    await waitForLoaderRequests(2, loader: loader)
    let didFailReload = await loader.failNext()
    XCTAssertTrue(didFailReload)
    await waitUntil("Failed reload should surface through SessionStore.") {
      if case .failed = launchedApp.sessionStore.phase {
        true
      } else {
        false
      }
    }
    XCTAssertTrue(
      coordinator.lastFailure?.diagnosticDescription?.contains("expected") == true
    )

    coordinator.requestSessionReload(source: source)
    await Task.yield()
    let requestCountAfterDuplicate = await loader.requestCount()
    XCTAssertEqual(requestCountAfterDuplicate, 2)

    coordinator.retrySessionReload(source: source)
    await waitForLoaderRequests(3, loader: loader)
    let didRetryReload = await loader.succeedNext(readySnapshot())
    XCTAssertTrue(didRetryReload)
    await waitUntil("Successful exact-source retry should restore readiness.") {
      launchedApp.sessionStore.phase == .ready
    }
    XCTAssertNil(coordinator.lastFailure)

    coordinator.requestSessionReload(source: source)
    await Task.yield()
    let finalRequestCount = await loader.requestCount()
    XCTAssertEqual(finalRequestCount, 3)
  }

  @MainActor
  func testReloadTimeoutRejectsLateResultAndRetriesExactSource() async throws {
    let container = try SendableModelContainer.inMemoryForTesting()
    let factory = ControlledContainerFactory()
    let loader = ControlledSnapshotLoader()
    let clock = ControlledLaunchClock()
    let coordinator = AppLaunchCoordinator(
      modelContainerFactory: factory,
      loaderFactory: FixedLoaderFactory(loader: loader),
      clock: clock
    )

    coordinator.start()
    await waitForFactoryRequests(1, factory: factory)
    await waitForClockSleepers(2, clock: clock)
    let didConstruct = await factory.succeedNext(container)
    XCTAssertTrue(didConstruct)
    await waitForLoaderRequests(1, loader: loader)
    await waitForClockSleepers(4, clock: clock)
    let didInstall = await loader.succeedNext(readySnapshot())
    XCTAssertTrue(didInstall)
    await waitUntil("Initial snapshot should install the app.") {
      if case .ready = coordinator.phase {
        true
      } else {
        false
      }
    }

    guard case .ready(let launchedApp) = coordinator.phase else {
      XCTFail("Expected a launched app.")
      return
    }

    let source = SessionReloadSource.routineMutation(UUID())
    let acknowledgement = Task { @MainActor () -> Result<Void, Error> in
      do {
        try await coordinator.awaitSessionReload(source: source)
        return .success(())
      } catch {
        return .failure(error)
      }
    }
    await waitForLoaderRequests(2, loader: loader)
    await waitForClockSleepers(6, clock: clock)
    await clock.advance(by: .seconds(8))
    await waitUntil("Reload timeout should surface through SessionStore.") {
      if case .failed = launchedApp.sessionStore.phase {
        true
      } else {
        false
      }
    }
    XCTAssertEqual(coordinator.lastFailure?.kind, .timedOut)
    let acknowledgementResult = await acknowledgement.value
    guard case .failure(
      let error as SessionReloadAcknowledgementError
    ) = acknowledgementResult else {
      return XCTFail("The timed-out exact-source acknowledgement should fail.")
    }
    XCTAssertEqual(error, .failed(source, .timedOut))

    let didFinishLate = await loader.succeedNext(readySnapshot())
    XCTAssertTrue(didFinishLate)
    await Task.yield()
    await Task.yield()
    if case .failed = launchedApp.sessionStore.phase {
    } else {
      XCTFail("A late reload result must not restore readiness.")
    }
    let requestCountAfterLateResult = await loader.requestCount()
    XCTAssertEqual(requestCountAfterLateResult, 2)

    coordinator.requestSessionReload(source: source)
    await Task.yield()
    let requestCountAfterDuplicate = await loader.requestCount()
    XCTAssertEqual(requestCountAfterDuplicate, 2)

    coordinator.retrySessionReload(source: source)
    await waitForLoaderRequests(3, loader: loader)
    let didRetry = await loader.succeedNext(readySnapshot())
    XCTAssertTrue(didRetry)
    await waitUntil("Exact-source retry should restore readiness.") {
      launchedApp.sessionStore.phase == .ready
    }
    XCTAssertNil(coordinator.lastFailure)
  }

  @MainActor
  func testAsyncReloadAcknowledgementReturnsOnlyAfterItsSnapshotApplies() async throws {
    let (coordinator, loader, launchedApp) = try await makeReadyCoordinator()
    let source = SessionReloadSource.onboardingCompletion(UUID())
    let snapshot = readySnapshot()
    let acknowledgement = Task { @MainActor () -> Result<Void, Error> in
      do {
        try await coordinator.awaitSessionReload(source: source)
        return .success(())
      } catch {
        return .failure(error)
      }
    }

    await waitForLoaderRequests(2, loader: loader)
    XCTAssertNotEqual(launchedApp.sessionStore.snapshot, snapshot)

    let didReload = await loader.succeedNext(snapshot)
    XCTAssertTrue(didReload)
    _ = try await acknowledgement.value.get()
    XCTAssertEqual(launchedApp.sessionStore.snapshot, snapshot)
  }

  @MainActor
  func testAsyncReloadAcknowledgementFailsForItsMatchingReloadFailure() async throws {
    let (coordinator, loader, launchedApp) = try await makeReadyCoordinator()
    let source = SessionReloadSource.routineMutation(UUID())
    let acknowledgement = Task { @MainActor () -> Result<Void, Error> in
      do {
        try await coordinator.awaitSessionReload(source: source)
        return .success(())
      } catch {
        return .failure(error)
      }
    }

    await waitForLoaderRequests(2, loader: loader)
    let didFail = await loader.failNext()
    XCTAssertTrue(didFail)

    guard case .failure(
      let error as SessionReloadAcknowledgementError
    ) = await acknowledgement.value else {
      return XCTFail("The matching reload failure should reject its acknowledgement.")
    }
    guard case .failed(let failedSource, let failure) = error else {
      return XCTFail("Expected a reload acknowledgement failure.")
    }
    XCTAssertEqual(failedSource, source)
    XCTAssertEqual(failure.kind, .session)
    if case .failed = launchedApp.sessionStore.phase {
    } else {
      XCTFail("The matching reload failure should be applied before acknowledgement.")
    }
  }

  @MainActor
  func testAsyncReloadAcknowledgementsDeduplicateAnExactSource() async throws {
    let (coordinator, loader, _) = try await makeReadyCoordinator()
    let source = SessionReloadSource.trialDismissal(UUID())
    let acknowledgements = (0..<2).map { _ in
      Task { @MainActor () -> Result<Void, Error> in
        do {
          try await coordinator.awaitSessionReload(source: source)
          return .success(())
        } catch {
          return .failure(error)
        }
      }
    }

    await waitForLoaderRequests(2, loader: loader)
    let requestCount = await loader.requestCount()
    XCTAssertEqual(requestCount, 2)
    let didReload = await loader.succeedNext(readySnapshot())
    XCTAssertTrue(didReload)

    for acknowledgement in acknowledgements {
      _ = try await acknowledgement.value.get()
    }

    try await coordinator.awaitSessionReload(source: source)
    let completedRequestCount = await loader.requestCount()
    XCTAssertEqual(completedRequestCount, 2)
  }

  @MainActor
  func testNonterminalResetJournalBlocksRegularLaunch() async throws {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AppLaunchCoordinatorTests-\(UUID().uuidString)",
      isDirectory: true
    )
    defer {
      try? FileManager.default.removeItem(at: directoryURL)
    }

    let journalStore = LocalResetJournalStore(
      fileURL: directoryURL.appendingPathComponent("journal.json", isDirectory: false)
    )
    _ = try journalStore.begin(operationID: UUID(), at: Date())
    let loader = ControlledSnapshotLoader()
    let coordinator = AppLaunchCoordinator(
      modelContainerFactory: StableContainerFactory(
        container: try SendableModelContainer.inMemoryForTesting()
      ),
      loaderFactory: FixedLoaderFactory(loader: loader),
      launchPreparation: DefaultAppLaunchPreparation(resetJournalStore: journalStore)
    )

    coordinator.start()
    await waitUntil("A nonterminal reset journal should block launch.") {
      if case .bootstrapFailed = coordinator.phase {
        true
      } else {
        false
      }
    }
    let loaderRequestCount = await loader.requestCount()
    XCTAssertEqual(loaderRequestCount, 0)
  }

  @MainActor
  func testCorruptResetJournalBlocksRegularLaunch() async throws {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AppLaunchCoordinatorTests-\(UUID().uuidString)",
      isDirectory: true
    )
    defer {
      try? FileManager.default.removeItem(at: directoryURL)
    }

    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    let journalURL = directoryURL.appendingPathComponent("journal.json", isDirectory: false)
    try Data("corrupt".utf8).write(to: journalURL)
    let loader = ControlledSnapshotLoader()
    let coordinator = AppLaunchCoordinator(
      modelContainerFactory: StableContainerFactory(
        container: try SendableModelContainer.inMemoryForTesting()
      ),
      loaderFactory: FixedLoaderFactory(loader: loader),
      launchPreparation: DefaultAppLaunchPreparation(
        resetJournalStore: LocalResetJournalStore(fileURL: journalURL)
      )
    )

    coordinator.start()
    await waitUntil("A corrupt reset journal should block launch.") {
      if case .bootstrapFailed = coordinator.phase {
        true
      } else {
        false
      }
    }
    let loaderRequestCount = await loader.requestCount()
    XCTAssertEqual(loaderRequestCount, 0)
  }

  @MainActor
  func testSnapshotWithoutPlatformStateRequiresRepairAndDoesNotInventGeneration() {
    let profile = sessionProfile()
    let routine = sessionRoutine(
      name: "플랫폼 상태 없는 루틴",
      scheduleID: UUID()
    )
    let snapshot = SessionSnapshot(
      profile: profile,
      activeRoutines: [routine],
      platformStates: [],
      settings: nil,
      resetGeneration: nil
    )
    let store = SessionStore()

    store.apply(snapshot: snapshot)

    XCTAssertNil(snapshot.settings)
    XCTAssertNil(snapshot.resetGeneration)
    XCTAssertFalse(SessionStore.isOnboardingComplete(snapshot: snapshot))
    XCTAssertEqual(store.phase, .alarmRepairRequired)
    XCTAssertNil(store.snapshot?.resetGeneration)
  }

  @MainActor
  private func makeReadyCoordinator() async throws -> (
    AppLaunchCoordinator,
    ControlledSnapshotLoader,
    LaunchedApp
  ) {
    let loader = ControlledSnapshotLoader()
    let coordinator = AppLaunchCoordinator(
      modelContainerFactory: StableContainerFactory(
        container: try SendableModelContainer.inMemoryForTesting()
      ),
      loaderFactory: FixedLoaderFactory(loader: loader)
    )

    coordinator.start()
    await waitForLoaderRequests(1, loader: loader)
    let didInstall = await loader.succeedNext(readySnapshot())
    XCTAssertTrue(didInstall)
    await waitUntil("Initial snapshot should install the app.") {
      if case .ready = coordinator.phase {
        true
      } else {
        false
      }
    }

    guard case .ready(let launchedApp) = coordinator.phase else {
      throw ControlledLaunchError.expected
    }
    return (coordinator, loader, launchedApp)
  }

  @MainActor
  private func waitForFactoryRequests(_ expected: Int, factory: ControlledContainerFactory) async {
    await waitUntil("Expected \(expected) container factory request(s).") {
      await factory.requestCount() == expected
    }
  }

  @MainActor
  private func waitForLoaderRequests(_ expected: Int, loader: ControlledSnapshotLoader) async {
    await waitUntil("Expected \(expected) session loader request(s).") {
      await loader.requestCount() == expected
    }
  }

  @MainActor
  private func waitForClockSleepers(_ expected: Int, clock: ControlledLaunchClock) async {
    await waitUntil("Expected \(expected) launch timer(s).") {
      await clock.sleeperCount() == expected
    }
  }

  @MainActor
  @discardableResult
  private func waitUntil(
    _ message: String,
    _ predicate: @escaping @MainActor () async -> Bool
  ) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(1))

    while clock.now < deadline {
      if await predicate() {
        return true
      }
      await Task.yield()
    }

    XCTFail(message)
    return false
  }

  @MainActor
  private func assertConstructing(_ coordinator: AppLaunchCoordinator) {
    guard case .constructing = coordinator.phase else {
      XCTFail("Coordinator should still be constructing.")
      return
    }
  }

  @MainActor
  private func assertLoading(
    _ coordinator: AppLaunchCoordinator,
    pending: PendingLaunchResources
  ) {
    guard case .loadingSession(let activePending) = coordinator.phase else {
      XCTFail("Coordinator should be loading a session.")
      return
    }
    XCTAssertTrue(activePending === pending)
  }

  @MainActor
  private func loadingPending(from coordinator: AppLaunchCoordinator) -> PendingLaunchResources? {
    guard case .loadingSession(let pending) = coordinator.phase else {
      return nil
    }
    return pending
  }

  @MainActor
  private func sessionFailurePending(
    from coordinator: AppLaunchCoordinator
  ) async -> PendingLaunchResources? {
    guard await waitUntil("Session failure should retain pending resources.", {
      if case .sessionFailed = coordinator.phase {
        true
      } else {
        false
      }
    }) else {
      return nil
    }

    guard case .sessionFailed(let pending, _) = coordinator.phase else {
      XCTFail("Session failure phase disappeared while reading its pending resources.")
      return nil
    }
    return pending
  }

  @MainActor
  private func readySnapshot() -> SessionSnapshot {
    let routineID = UUID()
    let scheduleID = UUID()
    let routine = sessionRoutine(
      id: routineID,
      name: "준비된 루틴",
      scheduleID: scheduleID
    )
    let platformState = AlarmPlatformSnapshot(
      id: UUID(),
      scheduleID: scheduleID,
      routineID: routineID,
      desiredScheduleFingerprint: "weekday-7-00",
      platformRequestID: UUID(),
      state: .configured,
      updatedAt: Date(),
      lastErrorCode: nil
    )

    return SessionSnapshot(
      profile: sessionProfile(),
      activeRoutines: [routine],
      platformStates: [platformState],
      settings: nil,
      resetGeneration: nil
    )
  }
  @MainActor
  private func sessionProfile() -> SessionProfileSnapshot {
    SessionProfileSnapshot(
      id: UUID(),
      displayName: "모루 사용자",
      selectedVoiceID: VoiceProfile.moru.id,
      createdAt: Date(),
      updatedAt: Date()
    )
  }

  @MainActor
  private func sessionRoutine(
    id: UUID = UUID(),
    name: String,
    scheduleID: UUID
  ) -> SessionRoutineSnapshot {
    SessionRoutineSnapshot(
      id: id,
      name: name,
      summary: "",
      goalTags: [],
      steps: [],
      alarmSchedule: SessionAlarmScheduleSnapshot(
        id: scheduleID,
        hour: 7,
        minute: 0,
        weekdays: [.monday],
        soundName: "moru-default",
        isEnabled: true,
        includeWeather: false,
        includeFortune: false
      ),
      isActive: true,
      createdAt: Date(),
      updatedAt: Date()
    )
  }
}

private enum ControlledLaunchError: Error {
  case expected
}

private actor ControlledContainerFactory: ModelContainerFactory {
  private var continuations: [CheckedContinuation<SendableModelContainer, Error>] = []
  private var requests = 0

  func makeContainer() async throws -> SendableModelContainer {
    requests += 1
    return try await withCheckedThrowingContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func requestCount() -> Int {
    requests
  }

  func succeedNext(_ container: SendableModelContainer) -> Bool {
    guard !continuations.isEmpty else {
      return false
    }

    continuations.removeFirst().resume(returning: container)
    return true
  }

  func failNext() -> Bool {
    guard !continuations.isEmpty else {
      return false
    }

    continuations.removeFirst().resume(throwing: ControlledLaunchError.expected)
    return true
  }
}

private actor StableContainerFactory: ModelContainerFactory {
  private let container: SendableModelContainer
  private var requests = 0

  init(container: SendableModelContainer) {
    self.container = container
  }

  func makeContainer() async throws -> SendableModelContainer {
    requests += 1
    return container
  }

  func requestCount() -> Int {
    requests
  }
}

private struct FixedLoaderFactory: SessionSnapshotLoaderFactory {
  let loader: ControlledSnapshotLoader

  func makeLoader(for container: SendableModelContainer) -> any SessionSnapshotLoader {
    loader
  }
}

private actor ControlledSnapshotLoader: SessionSnapshotLoader {
  private var continuations: [CheckedContinuation<SessionSnapshot, Error>] = []
  private var requests = 0

  func loadSnapshot() async throws -> SessionSnapshot {
    requests += 1
    return try await withCheckedThrowingContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func requestCount() -> Int {
    requests
  }

  func succeedNext(_ snapshot: SessionSnapshot) -> Bool {
    guard !continuations.isEmpty else {
      return false
    }

    continuations.removeFirst().resume(returning: snapshot)
    return true
  }

  func failNext() -> Bool {
    guard !continuations.isEmpty else {
      return false
    }

    continuations.removeFirst().resume(throwing: ControlledLaunchError.expected)
    return true
  }
}

private actor ControlledLaunchClock: AppLaunchClock {
  private struct Sleeper {
    let deadline: Duration
    let continuation: CheckedContinuation<Void, Error>
  }

  private var elapsed: Duration = .zero
  private var sleepers: [Sleeper] = []

  func sleep(for duration: Duration) async throws {
    let deadline = elapsed + duration
    try await withCheckedThrowingContinuation { continuation in
      sleepers.append(Sleeper(deadline: deadline, continuation: continuation))
    }
  }

  func sleeperCount() -> Int {
    sleepers.count
  }

  func advance(by duration: Duration) {
    elapsed += duration
    var pending: [Sleeper] = []
    var ready: [Sleeper] = []

    for sleeper in sleepers {
      if sleeper.deadline <= elapsed {
        ready.append(sleeper)
      } else {
        pending.append(sleeper)
      }
    }

    sleepers = pending
    ready.forEach { $0.continuation.resume() }
  }

  func failAll() {
    let pending = sleepers
    sleepers.removeAll()
    pending.forEach {
      $0.continuation.resume(throwing: ControlledLaunchError.expected)
    }
  }
}
