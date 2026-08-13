//
//  HomeRoutineServerNoticeTests.swift
//  MoruTests
//

import Foundation
import SwiftUI
import XCTest
@testable import Moru

final class HomeRoutineServerNoticeTests: XCTestCase {
  @MainActor
  func testOnlyPendingWorkAndRemoteUnavailabilityProduceNotices() {
    XCTAssertEqual(HomeRoutineServerState.loading.notice, .syncing)
    XCTAssertEqual(
      HomeRoutineServerState.fallback(.pendingLocalExecution).notice,
      .syncing
    )
    XCTAssertEqual(
      HomeRoutineServerState.fallback(.remoteUnavailable).notice,
      .showingSavedRoutines
    )

    let statesWithoutNotice: [HomeRoutineServerState] = [
      .notConfigured,
      .applied,
      .noActive,
      .fallback(.signedOut),
      .fallback(.localActiveMissing),
      .fallback(.localActiveAmbiguous),
      .fallback(.remoteHasNoActiveLocalHasActive),
      .fallback(.activeGroupBindingMissing),
      .fallback(.activeGroupIdentityMismatch),
      .fallback(.activeRoutineBindingMissing),
      .fallback(.activeRoutineIdentityMismatch),
      .fallback(.inconsistentRemoteSnapshot),
      .fallback(.localSyncStateUnavailable),
      .fallback(.serverProjectionDayMismatch),
    ]

    for state in statesWithoutNotice {
      XCTAssertNil(state.notice, "Unexpected notice for \(state)")
    }
  }

  @MainActor
  func testNoticeCopyAndRetryContractRemainTruthful() {
    XCTAssertEqual(
      HomeRoutineServerNotice.syncing.message,
      "루틴을 동기화하고 있어요."
    )
    XCTAssertFalse(HomeRoutineServerNotice.syncing.canRetry)
    XCTAssertEqual(
      HomeRoutineServerNotice.showingSavedRoutines.message,
      "서버 정보를 확인할 수 없어요."
    )
    XCTAssertTrue(HomeRoutineServerNotice.showingSavedRoutines.canRetry)
  }

  @MainActor
  func testSavedRoutineFallbackIsAnnouncedOnlyWhenItAppears() {
    var announcements: [String] = []
    let boundary = HomeRoutineServerNoticeBoundary(
      announceAccessibility: { announcements.append($0) }
    )

    boundary.noticeDidChange(from: nil, to: .syncing)
    boundary.noticeDidChange(from: .syncing, to: .showingSavedRoutines)
    boundary.noticeDidChange(
      from: .showingSavedRoutines,
      to: .showingSavedRoutines
    )
    boundary.noticeDidChange(from: .showingSavedRoutines, to: nil)

    XCTAssertEqual(
      announcements,
      [HomeRoutineServerNotice.showingSavedRoutinesMessage]
    )
  }

  @MainActor
  func testNoticeAccessibilityIdentifiersAreStable() {
    XCTAssertEqual(
      HomeView.routineSyncingAccessibilityIdentifier,
      "home.routine-sync.syncing"
    )
    XCTAssertEqual(
      HomeView.routineSavedDataAccessibilityIdentifier,
      "home.routine-sync.saved-data"
    )
    XCTAssertEqual(
      HomeView.routineServerRetryAccessibilityIdentifier,
      "home.routine-sync.retry"
    )
  }

  @MainActor
  func testNoticesRenderInContentAndEmptyAtSupportedTextSizes() async throws {
    let outputDirectory = URL(
      fileURLWithPath: "/tmp/moru-home-routine-server-notices",
      isDirectory: true
    )
    let variants = MoruVisualCaptureVariant.allCases

    let syncingEnricher = NoticeSequenceEnricher()
    let syncingViewModel = HomeViewModel(
      loadHomeRoutinesUseCase: NoticeHomeLoadUseCase(
        result: makeNoticeHomeResult(hasRoutine: true)
      ),
      enrichHomeRoutinesUseCase: syncingEnricher
    )
    syncingViewModel.load()
    await syncingEnricher.waitForRequestCount(1)
    XCTAssertEqual(syncingViewModel.routineServerState.notice, .syncing)

    for variant in variants {
      let image = try MoruVisualCaptureFixture.render(
        noticeHomeView(viewModel: syncingViewModel),
        filename: "syncing-\(variant.rawValue).png",
        variant: variant,
        outputDirectory: outputDirectory
      )
      XCTAssertEqual(image.size, MoruVisualCaptureConfiguration.iPhone16.size)
    }

    syncingEnricher.resume(at: 0, returning: .noActive)
    await waitUntil { syncingViewModel.routineServerState == .noActive }

    let savedDataEnricher = NoticeSequenceEnricher()
    let savedDataViewModel = HomeViewModel(
      loadHomeRoutinesUseCase: NoticeHomeLoadUseCase(
        result: makeNoticeHomeResult(hasRoutine: false)
      ),
      enrichHomeRoutinesUseCase: savedDataEnricher
    )
    savedDataViewModel.load()
    await savedDataEnricher.waitForRequestCount(1)
    savedDataEnricher.resume(
      at: 0,
      returning: .fallback(.remoteUnavailable)
    )
    await waitUntil {
      savedDataViewModel.routineServerState.notice == .showingSavedRoutines
    }

    for variant in variants {
      let image = try MoruVisualCaptureFixture.render(
        noticeHomeView(viewModel: savedDataViewModel),
        filename: "saved-data-empty-\(variant.rawValue).png",
        variant: variant,
        outputDirectory: outputDirectory
      )
      XCTAssertEqual(image.size, MoruVisualCaptureConfiguration.iPhone16.size)
    }

    savedDataViewModel.retry()
    await savedDataEnricher.waitForRequestCount(2)
    XCTAssertEqual(savedDataViewModel.routineServerState.notice, .syncing)
    savedDataEnricher.resume(at: 1, returning: .noActive)
    await waitUntil { savedDataViewModel.routineServerState == .noActive }
  }

  @MainActor
  private func noticeHomeView(
    viewModel: HomeViewModel
  ) -> some View {
    HomeView(
      viewModel: viewModel,
      onStartRoutine: { _ in .started },
      refreshToken: 0,
      routineSettingContent: AnyView(EmptyView()),
      automaticallyLoads: false
    )
  }

  @MainActor
  private func makeNoticeHomeResult(
    hasRoutine: Bool
  ) -> HomeRoutineLoadResult {
    let routine = Routine(
      name: "아침 루틴",
      steps: [
        RoutineStep(
          type: .confirm,
          title: "물 한 잔 마시기",
          order: 0,
          estimatedSeconds: 60
        ),
      ]
    )

    return HomeRoutineLoadResult(
      profile: LocalProfile(displayName: "모루"),
      todayRoutine: hasRoutine ? routine : nil,
      manualRoutines: hasRoutine ? [routine] : [],
      todayRunsByRoutineID: [:],
      streak: RoutineStreak(
        currentDays: 0,
        bestDays: 0,
        completedWeekdays: []
      )
    )
  }

  @MainActor
  private func waitUntil(
    _ predicate: @escaping @MainActor () -> Bool
  ) async {
    for _ in 0..<1_000 where !predicate() {
      await Task.yield()
    }
    XCTAssertTrue(predicate(), "Timed out waiting for Home notice state.")
  }
}

@MainActor
private final class NoticeHomeLoadUseCase: LoadHomeRoutinesUseCaseProtocol {
  private let result: HomeRoutineLoadResult

  init(result: HomeRoutineLoadResult) {
    self.result = result
  }

  func execute() throws -> HomeRoutineLoadResult {
    result
  }
}

@MainActor
private final class NoticeSequenceEnricher: EnrichHomeRoutinesUseCaseProtocol {
  private var continuations: [
    CheckedContinuation<HomeRoutineServerEnrichment, Error>?
  ] = []

  func execute(
    localResult: HomeRoutineLoadResult
  ) async throws -> HomeRoutineServerEnrichment {
    try await withCheckedThrowingContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func waitForRequestCount(_ count: Int) async {
    for _ in 0..<1_000 where continuations.count < count {
      await Task.yield()
    }
    XCTAssertGreaterThanOrEqual(
      continuations.count,
      count,
      "Timed out waiting for Home enrichment request."
    )
  }

  func resume(
    at index: Int,
    returning result: HomeRoutineServerEnrichment
  ) {
    continuations[index]?.resume(returning: result)
    continuations[index] = nil
  }
}
