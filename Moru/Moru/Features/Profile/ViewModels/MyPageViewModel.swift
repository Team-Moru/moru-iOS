//
//  MyPageViewModel.swift
//  Moru
//
//  Created by Codex on 7/13/26.
//

import Foundation
import Observation

@MainActor
@Observable
final class MyPageViewModel {
  private let localProfileRepository: any LocalProfileRepository
  private let resetLocalDataUseCase: ResetLocalDataUseCase

  var state: MyPageViewState = .placeholder

  init(dependencies: DependencyContainer) {
    self.localProfileRepository = dependencies.localProfileRepository
    self.resetLocalDataUseCase = ResetLocalDataUseCase(
      localDataResetRepository: dependencies.localDataResetRepository
    )
  }

  func load() {
    state.isLoading = true
    state.errorMessage = nil

    do {
      let profile = try localProfileRepository.loadOrCreateDefaultProfile()
      state = MyPageViewState(
        displayName: profile.displayName,
        selectedVoice: profile.selectedVoice,
        availableVoices: VoiceProfile.localVoices,
        isLoading: false,
        errorMessage: nil
      )
    } catch {
      state.isLoading = false
      state.errorMessage = "프로필 정보를 불러오지 못했어요."
    }
  }

  func selectVoice(_ voice: VoiceProfile) {
    do {
      var profile = try localProfileRepository.loadOrCreateDefaultProfile()
      profile.selectedVoice = voice
      profile.updatedAt = Date()
      try localProfileRepository.saveProfile(profile)
      load()
    } catch {
      state.errorMessage = "음성 설정을 저장하지 못했어요."
    }
  }

  @discardableResult
  func updateDisplayName(_ displayName: String) -> Bool {
    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      state.errorMessage = "이름을 입력해 주세요."
      return false
    }

    do {
      var profile = try localProfileRepository.loadOrCreateDefaultProfile()
      profile.displayName = trimmedName
      profile.updatedAt = Date()
      try localProfileRepository.saveProfile(profile)
      load()
      return true
    } catch {
      state.errorMessage = "프로필 정보를 저장하지 못했어요."
      return false
    }
  }

  @discardableResult
  func resetLocalData() -> Bool {
    do {
      try resetLocalDataUseCase.reset()
      state = .placeholder
      return true
    } catch {
      state.errorMessage = "초기화에 실패했어요. 기존 데이터는 유지됩니다."
      return false
    }
  }
}
