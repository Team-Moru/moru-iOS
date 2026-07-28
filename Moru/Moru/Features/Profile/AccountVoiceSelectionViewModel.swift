//
//  AccountVoiceSelectionViewModel.swift
//  Moru
//

import Observation
import UIKit

@MainActor
@Observable
final class AccountVoiceSelectionViewModel {
  private let useCase: any AccountVoiceSelectionUseCaseProtocol
  private let previewPlayer: any VoicePreviewPlaying
  private var profileUpdatedHandler:
    (@MainActor (ProfileSettingsLoadResult) -> Void)?
  private var stateGeneration = 0
  private var selectionGeneration = 0
  private var isResolvingMismatch = false

  private(set) var catalogue = AccountVoiceCatalogueSnapshot(
    options: [],
    mismatch: nil,
    notice: nil
  )
  private(set) var isLoading = false
  private(set) var isSelecting = false
  private(set) var errorMessage: String?

  init(
    useCase: any AccountVoiceSelectionUseCaseProtocol,
    previewPlayer: any VoicePreviewPlaying
  ) {
    self.useCase = useCase
    self.previewPlayer = previewPlayer
  }

  func setProfileUpdatedHandler(
    _ handler: (@MainActor (ProfileSettingsLoadResult) -> Void)?
  ) {
    profileUpdatedHandler = handler
  }

  func viewDidAppear() async {
    let generation = beginStateOperation()
    isLoading = true
    let snapshot = await useCase.loadCatalogue()

    guard isCurrent(generation), !Task.isCancelled else {
      finishCancelledOperation(generation)
      return
    }

    catalogue = snapshot
    isLoading = false
  }

  func select(_ option: AccountVoiceOption) async -> Bool {
    guard !isSelecting else {
      return false
    }
    isSelecting = true
    defer {
      isSelecting = false
    }

    let stateGeneration = beginStateOperation()
    let selectionGeneration = beginSelectionOperation()
    isLoading = false
    errorMessage = nil

    do {
      let result = try await useCase.select(option)
      guard isCurrentSelection(selectionGeneration) else {
        return false
      }

      profileUpdatedHandler?(result.profileResult)
      guard isCurrent(stateGeneration), !Task.isCancelled else {
        return false
      }

      previewPlayer.stopVoicePreview()
      if result.serverDisposition == .queueFailed {
        reportError(
          "기기에는 저장했지만 서버 반영 대기를 등록하지 못했어요."
        )
      }
      let snapshot = await useCase.loadCatalogue()
      guard isCurrent(stateGeneration), !Task.isCancelled else {
        return false
      }
      catalogue = snapshot
      return snapshot.mismatch == nil
    } catch {
      guard isCurrentSelection(selectionGeneration),
            isCurrent(stateGeneration),
            !Task.isCancelled else {
        return false
      }
      reportError("이 목소리는 지금 선택할 수 없어요.")
      return false
    }
  }

  func preview(_ option: AccountVoiceOption) {
    errorMessage = nil

    guard let voice = option.localVoice,
          option.availability.isSelectable,
          previewPlayer.previewVoice(voice) else {
      reportError("이 목소리를 미리 들을 수 없어요.")
      return
    }
  }

  func resolveMismatch(
    _ mismatch: AccountVoiceMismatch,
    _ choice: AccountVoiceMismatchChoice
  ) async {
    guard !isSelecting else {
      isResolvingMismatch = false
      return
    }
    isSelecting = true
    defer {
      isResolvingMismatch = false
      isSelecting = false
    }

    let stateGeneration = beginStateOperation()
    let selectionGeneration = beginSelectionOperation()
    do {
      let result = try await useCase.resolveMismatch(
        mismatch,
        choice: choice
      )
      guard isCurrentSelection(selectionGeneration) else {
        return
      }

      profileUpdatedHandler?(result.profileResult)
      guard isCurrent(stateGeneration), !Task.isCancelled else {
        return
      }

      if result.serverDisposition == .queueFailed {
        reportError(
          "기기에는 저장했지만 서버 반영 대기를 등록하지 못했어요."
        )
      }
      let snapshot = await useCase.loadCatalogue()
      guard isCurrent(stateGeneration), !Task.isCancelled else {
        return
      }
      catalogue = snapshot
    } catch {
      guard isCurrentSelection(selectionGeneration),
            isCurrent(stateGeneration),
            !Task.isCancelled else {
        return
      }
      reportError("음성 선택 차이를 처리하지 못했어요.")
    }
  }

  func mismatchResolutionWillBegin() {
    isResolvingMismatch = true
  }

  func mismatchDialogDidDismiss() {
    if isResolvingMismatch {
      catalogue = AccountVoiceCatalogueSnapshot(
        options: catalogue.options,
        mismatch: nil,
        notice: catalogue.notice
      )
      return
    }

    _ = beginStateOperation()
    isLoading = false
    catalogue = AccountVoiceCatalogueSnapshot(
      options: catalogue.options,
      mismatch: nil,
      notice: catalogue.notice
    )
  }

  func viewDidDisappear() {
    _ = beginStateOperation()
    isResolvingMismatch = false
    isLoading = false
    previewPlayer.stopVoicePreview()
  }

  private func reportError(_ message: String) {
    errorMessage = message
    UIAccessibility.post(notification: .announcement, argument: message)
  }

  @discardableResult
  private func beginStateOperation() -> Int {
    stateGeneration += 1
    return stateGeneration
  }

  private func isCurrent(_ generation: Int) -> Bool {
    stateGeneration == generation
  }

  @discardableResult
  private func beginSelectionOperation() -> Int {
    selectionGeneration += 1
    return selectionGeneration
  }

  private func isCurrentSelection(_ generation: Int) -> Bool {
    selectionGeneration == generation
  }

  private func finishCancelledOperation(_ generation: Int) {
    guard isCurrent(generation) else {
      return
    }

    stateGeneration += 1
    isLoading = false
  }
}
