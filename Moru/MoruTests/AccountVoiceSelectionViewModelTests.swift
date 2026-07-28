//
//  AccountVoiceSelectionViewModelTests.swift
//  MoruTests
//

import XCTest

@testable import Moru

@MainActor
final class AccountVoiceSelectionViewModelTests: XCTestCase {
  func testChildStateLoadsSelectsAndNotifiesProfileOwner() async throws {
    let option = makeOption()
    let profileResult = ProfileSettingsLoadResult(
      profile: LocalProfile(selectedVoice: .aoede),
      fallbackNotice: nil
    )
    let useCase = AccountVoiceSelectionUseCaseSpy(
      snapshot: AccountVoiceCatalogueSnapshot(
        options: [option],
        mismatch: nil,
        notice: "저장된 목록"
      ),
      selectionResult: .success(
        VoiceSelectionCommitResult(
          profileResult: profileResult,
          serverDisposition: .queued
        )
      )
    )
    let previewPlayer = AccountVoicePreviewPlayerSpy()
    let viewModel = AccountVoiceSelectionViewModel(
      useCase: useCase,
      previewPlayer: previewPlayer
    )
    var observedProfile: LocalProfile?
    viewModel.setProfileUpdatedHandler { result in
      observedProfile = result.profile
    }

    await viewModel.viewDidAppear()

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertEqual(viewModel.catalogue.options, [option])
    XCTAssertEqual(viewModel.catalogue.notice, "저장된 목록")

    viewModel.preview(option)
    XCTAssertEqual(previewPlayer.previewedVoices, [.aoede])

    let didSelect = await viewModel.select(option)
    XCTAssertTrue(didSelect)
    XCTAssertEqual(observedProfile, profileResult.profile)
    XCTAssertEqual(useCase.selectedOptions, [option])
    XCTAssertNil(viewModel.errorMessage)

    viewModel.viewDidDisappear()
    XCTAssertEqual(previewPlayer.stopCount, 2)
  }

  func testQueueFailureKeepsCommittedProfileAndReportsRecoverableError()
    async throws {
    let option = makeOption()
    let profileResult = ProfileSettingsLoadResult(
      profile: LocalProfile(selectedVoice: .aoede),
      fallbackNotice: nil
    )
    let useCase = AccountVoiceSelectionUseCaseSpy(
      snapshot: AccountVoiceCatalogueSnapshot(
        options: [option],
        mismatch: nil,
        notice: nil
      ),
      selectionResult: .success(
        VoiceSelectionCommitResult(
          profileResult: profileResult,
          serverDisposition: .queueFailed
        )
      )
    )
    let viewModel = AccountVoiceSelectionViewModel(
      useCase: useCase,
      previewPlayer: AccountVoicePreviewPlayerSpy()
    )
    var observedProfile: LocalProfile?
    viewModel.setProfileUpdatedHandler { result in
      observedProfile = result.profile
    }

    let didSelect = await viewModel.select(option)
    XCTAssertTrue(didSelect)

    XCTAssertEqual(observedProfile, profileResult.profile)
    XCTAssertEqual(
      viewModel.errorMessage,
      "기기에는 저장했지만 서버 반영 대기를 등록하지 못했어요."
    )
  }

  func testSelectionBusyStateRejectsDuplicateInputUntilSynchronizationFinishes()
    async {
    let option = makeOption()
    let profileResult = ProfileSettingsLoadResult(
      profile: LocalProfile(selectedVoice: .aoede),
      fallbackNotice: nil
    )
    let useCase = GatedAccountVoiceSelectionUseCase(
      snapshot: AccountVoiceCatalogueSnapshot(
        options: [option],
        mismatch: nil,
        notice: nil
      )
    )
    let viewModel = AccountVoiceSelectionViewModel(
      useCase: useCase,
      previewPlayer: AccountVoicePreviewPlayerSpy()
    )
    let firstSelection = Task {
      await viewModel.select(option)
    }
    await useCase.waitUntilSelectionRequested()

    XCTAssertTrue(viewModel.isSelecting)
    let duplicateResult = await viewModel.select(option)
    XCTAssertFalse(duplicateResult)
    XCTAssertEqual(useCase.selectionRequestCount, 1)

    useCase.finishSelection(
      VoiceSelectionCommitResult(
        profileResult: profileResult,
        serverDisposition: .queued
      )
    )

    let firstResult = await firstSelection.value
    XCTAssertTrue(firstResult)
    XCTAssertFalse(viewModel.isSelecting)
    XCTAssertEqual(useCase.selectionRequestCount, 1)
  }

  private func makeOption() -> AccountVoiceOption {
    AccountVoiceOption(
      id: "bundled.\(VoiceProfile.aoede.id)",
      serverMemberID: nil,
      serverVoiceCode: nil,
      serverTtsID: nil,
      displayName: VoiceProfile.aoede.displayName,
      detail: "앱 내장 음성",
      localVoice: .aoede,
      availability: .selectable,
      source: .bundledFallback,
      isAuthoritativeServerSelection: false
    )
  }
}

@MainActor
private final class GatedAccountVoiceSelectionUseCase:
  AccountVoiceSelectionUseCaseProtocol {
  private let snapshot: AccountVoiceCatalogueSnapshot
  private var selectionContinuation:
    CheckedContinuation<VoiceSelectionCommitResult, Never>?
  private var selectionWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var selectionRequestCount = 0

  init(snapshot: AccountVoiceCatalogueSnapshot) {
    self.snapshot = snapshot
  }

  func loadCatalogue() async -> AccountVoiceCatalogueSnapshot {
    snapshot
  }

  func select(
    _ option: AccountVoiceOption
  ) async throws -> VoiceSelectionCommitResult {
    selectionRequestCount += 1
    selectionWaiters.forEach { $0.resume() }
    selectionWaiters.removeAll()

    return await withCheckedContinuation { continuation in
      selectionContinuation = continuation
    }
  }

  func resolveMismatch(
    _ mismatch: AccountVoiceMismatch,
    choice: AccountVoiceMismatchChoice
  ) async throws -> VoiceSelectionCommitResult {
    try await select(mismatch.serverVoice)
  }

  func waitUntilSelectionRequested() async {
    guard selectionRequestCount == 0 else {
      return
    }

    await withCheckedContinuation { continuation in
      selectionWaiters.append(continuation)
    }
  }

  func finishSelection(_ result: VoiceSelectionCommitResult) {
    selectionContinuation?.resume(returning: result)
    selectionContinuation = nil
  }
}

@MainActor
private final class AccountVoiceSelectionUseCaseSpy:
  AccountVoiceSelectionUseCaseProtocol {
  private let snapshot: AccountVoiceCatalogueSnapshot
  private let selectionResult: Result<VoiceSelectionCommitResult, Error>
  private(set) var selectedOptions: [AccountVoiceOption] = []

  init(
    snapshot: AccountVoiceCatalogueSnapshot,
    selectionResult: Result<VoiceSelectionCommitResult, Error>
  ) {
    self.snapshot = snapshot
    self.selectionResult = selectionResult
  }

  func loadCatalogue() async -> AccountVoiceCatalogueSnapshot {
    snapshot
  }

  func select(
    _ option: AccountVoiceOption
  ) async throws -> VoiceSelectionCommitResult {
    selectedOptions.append(option)
    return try selectionResult.get()
  }

  func resolveMismatch(
    _ mismatch: AccountVoiceMismatch,
    choice: AccountVoiceMismatchChoice
  ) async throws -> VoiceSelectionCommitResult {
    try selectionResult.get()
  }
}

@MainActor
private final class AccountVoicePreviewPlayerSpy: VoicePreviewPlaying {
  private(set) var previewedVoices: [VoiceProfile] = []
  private(set) var stopCount = 0

  func previewVoice(_ voice: VoiceProfile) -> Bool {
    previewedVoices.append(voice)
    return true
  }

  func stopVoicePreview() {
    stopCount += 1
  }
}
