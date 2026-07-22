//
//  ProfileSettingsTests.swift
//  MoruTests
//
//  Created by Codex on 7/22/26.
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

final class ProfileSettingsTests: XCTestCase {
  @MainActor
  func testDisplayNameIsTrimmedAndInvalidNamesAreRejected() throws {
    let repository = ProfileTestProfileRepository(
      profile: LocalProfile(displayName: "기존 이름")
    )
    let useCase = ProfileSettingsUseCase(
      localProfileRepository: repository,
      voiceAvailabilityProbe: ProfileTestVoiceProbe(
        availableVoiceIDs: [VoiceProfile.yuna.id]
      ),
      now: { Date(timeIntervalSince1970: 100) }
    )

    let result = try useCase.saveDisplayName("  새 이름  ")

    XCTAssertEqual(result.profile.displayName, "새 이름")
    XCTAssertEqual(repository.profile?.displayName, "새 이름")
    XCTAssertEqual(repository.profile?.updatedAt, Date(timeIntervalSince1970: 100))
    assertDisplayNameError(.empty) {
      _ = try useCase.saveDisplayName("   ")
    }
    assertDisplayNameError(.tooLong) {
      _ = try useCase.saveDisplayName(String(repeating: "가", count: 21))
    }
    assertDisplayNameError(.containsEmoji) {
      _ = try useCase.saveDisplayName("모루😀")
    }
    assertDisplayNameError(.containsControlCharacter) {
      _ = try useCase.saveDisplayName("모루\n사용자")
    }
  }

  @MainActor
  func testUnavailableStoredVoiceFallsBackToFirstAvailableLocalVoice() throws {
    let repository = ProfileTestProfileRepository(
      profile: LocalProfile(selectedVoice: .moru)
    )
    let useCase = ProfileSettingsUseCase(
      localProfileRepository: repository,
      voiceAvailabilityProbe: ProfileTestVoiceProbe(
        availableVoiceIDs: [VoiceProfile.sora.id]
      )
    )

    let result = try useCase.loadProfileSettings()

    XCTAssertEqual(result.profile.selectedVoice, VoiceProfile.sora)
    XCTAssertEqual(repository.profile?.selectedVoice, VoiceProfile.sora)
    XCTAssertNotNil(result.fallbackNotice)
    XCTAssertThrowsError(try useCase.selectVoice(VoiceProfile.yuna)) { error in
      XCTAssertEqual(
        error as? ProfileSettingsUseCaseError,
        .unavailableVoice(VoiceProfile.yuna.id)
      )
    }
  }

  @MainActor
  func testResetCancelsAlarmsBeforeDeletingData() async throws {
    let recorder = ProfileTestEventRecorder()
    let alarmService = ProfileTestAlarmService(recorder: recorder)
    let resetRepository = ProfileTestResetRepository(recorder: recorder)
    let useCase = ResetLocalDataUseCase(
      localDataResetRepository: resetRepository,
      alarmService: alarmService
    )

    try await useCase.execute()

    XCTAssertEqual(recorder.events, ["cancel alarms", "reset data"])
  }

  @MainActor
  func testResetStopsBeforeDeletingDataWhenAlarmCancellationFails() async {
    let recorder = ProfileTestEventRecorder()
    let alarmService = ProfileTestAlarmService(
      recorder: recorder,
      cancellationError: ProfileTestError.unavailable
    )
    let resetRepository = ProfileTestResetRepository(recorder: recorder)
    let useCase = ResetLocalDataUseCase(
      localDataResetRepository: resetRepository,
      alarmService: alarmService
    )

    do {
      try await useCase.execute()
      XCTFail("Reset should fail when alarms cannot be cancelled.")
    } catch {
      XCTAssertEqual(recorder.events, ["cancel alarms"])
    }
  }

  @MainActor
  func testProfileViewModelStopsPreviewAndRequestsAlarmAuthorization() async {
    let profileUseCase = ProfileTestSettingsUseCase()
    let previewPlayer = ProfileTestVoicePreviewPlayer()
    let alarmService = ProfileTestAlarmService(
      status: .permissionNotDetermined,
      requestedStatus: .configured
    )
    let viewModel = makeViewModel(
      profileUseCase: profileUseCase,
      previewPlayer: previewPlayer,
      alarmService: alarmService
    )

    viewModel.voicePreviewButtonDidTap(.yuna)
    viewModel.voiceSelectionViewDidDisappear()
    await viewModel.alarmAuthorizationButtonDidTap()

    XCTAssertEqual(previewPlayer.previewedVoices, [.yuna])
    XCTAssertEqual(previewPlayer.stopCallCount, 1)
    XCTAssertEqual(alarmService.requestCallCount, 1)
    XCTAssertEqual(viewModel.alarmStatus, .configured)
  }

  @MainActor
  func testProfileViewModelBlocksResetDuringAnotherPresentation() async {
    let resetUseCase = ProfileTestResetUseCase()
    let viewModel = makeViewModel(
      resetUseCase: resetUseCase,
      resetAvailability: { false }
    )

    await viewModel.resetConfirmationButtonDidTap()

    XCTAssertEqual(resetUseCase.executeCallCount, 0)
    XCTAssertEqual(
      viewModel.resetErrorMessage,
      "진행 중인 루틴이 끝난 후 초기화해 주세요."
    )
  }

  @MainActor
  func testSwiftDataResetDeletesProfileRoutinesAndRunsTogether() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    let profileRepository = SwiftDataLocalProfileRepository(modelContext: context)
    let routineRepository = SwiftDataRoutineRepository(modelContext: context)
    let runRepository = SwiftDataRoutineRunRepository(modelContext: context)
    let resetRepository = SwiftDataLocalDataResetRepository(modelContext: context)
    let routine = Routine(
      name: "초기화 테스트",
      steps: [RoutineStep(type: .confirm, title: "물 마시기", order: 0)]
    )

    try profileRepository.saveProfile(LocalProfile())
    try routineRepository.saveRoutine(routine)
    try runRepository.saveRun(RoutineRun(routine: routine))

    try resetRepository.resetToFreshInstallState()

    XCTAssertNil(try profileRepository.fetchProfile())
    XCTAssertEqual(try routineRepository.fetchRoutines(), [])
    XCTAssertEqual(try runRepository.fetchRuns(), [])
  }

  @MainActor
  private func assertDisplayNameError(
    _ expected: ProfileDisplayNameValidationError,
    action: () throws -> Void
  ) {
    XCTAssertThrowsError(try action()) { error in
      XCTAssertEqual(
        error as? ProfileSettingsUseCaseError,
        .invalidDisplayName(expected)
      )
    }
  }

  @MainActor
  private func makeViewModel(
    profileUseCase: ProfileTestSettingsUseCase = ProfileTestSettingsUseCase(),
    previewPlayer: ProfileTestVoicePreviewPlayer = ProfileTestVoicePreviewPlayer(),
    alarmService: ProfileTestAlarmService = ProfileTestAlarmService(),
    resetUseCase: ProfileTestResetUseCase? = nil,
    resetAvailability: @escaping @MainActor () -> Bool = { true }
  ) -> ProfileViewModel {
    ProfileViewModel(
      profileSettingsUseCase: profileUseCase,
      voicePreviewPlayer: previewPlayer,
      alarmService: alarmService,
      resetUseCase: resetUseCase,
      resetAvailability: resetAvailability,
      onOpenSettings: {},
      onResetSucceeded: {}
    )
  }
}

private enum ProfileTestError: Error {
  case unavailable
}

@MainActor
private final class ProfileTestProfileRepository: LocalProfileRepository {
  var profile: LocalProfile?

  init(profile: LocalProfile?) {
    self.profile = profile
  }

  func fetchProfile() throws -> LocalProfile? {
    profile
  }

  func loadOrCreateDefaultProfile() throws -> LocalProfile {
    if let profile {
      return profile
    }

    let profile = LocalProfile()
    self.profile = profile
    return profile
  }

  func saveProfile(_ profile: LocalProfile) throws {
    self.profile = profile
  }

  func deleteProfile() throws {
    profile = nil
  }
}

private struct ProfileTestVoiceProbe: VoiceAvailabilityProbing {
  let availableVoiceIDs: Set<String>

  func isAvailable(_ voice: VoiceProfile) -> Bool {
    availableVoiceIDs.contains(voice.id)
  }
}

@MainActor
private final class ProfileTestEventRecorder {
  var events: [String] = []
}

@MainActor
private final class ProfileTestResetRepository: LocalDataResetRepository {
  private let recorder: ProfileTestEventRecorder

  init(recorder: ProfileTestEventRecorder) {
    self.recorder = recorder
  }

  func resetToFreshInstallState() throws {
    recorder.events.append("reset data")
  }
}

@MainActor
private final class ProfileTestAlarmService: ProfileAlarmServicing {
  private let recorder: ProfileTestEventRecorder?
  private let cancellationError: Error?
  private let requestedStatus: ProfileAlarmStatus
  private(set) var status: ProfileAlarmStatus
  private(set) var requestCallCount = 0

  init(
    recorder: ProfileTestEventRecorder? = nil,
    cancellationError: Error? = nil,
    status: ProfileAlarmStatus = .configured,
    requestedStatus: ProfileAlarmStatus = .configured
  ) {
    self.recorder = recorder
    self.cancellationError = cancellationError
    self.status = status
    self.requestedStatus = requestedStatus
  }

  func currentStatus() -> ProfileAlarmStatus {
    status
  }

  func requestAuthorization() async -> ProfileAlarmStatus {
    requestCallCount += 1
    status = requestedStatus
    return status
  }

  func cancelAllAlarms() throws {
    recorder?.events.append("cancel alarms")
    if let cancellationError {
      throw cancellationError
    }
  }
}

@MainActor
private final class ProfileTestSettingsUseCase: ProfileSettingsUseCaseProtocol {
  private(set) var result = ProfileSettingsLoadResult(
    profile: LocalProfile(),
    fallbackNotice: nil
  )

  func loadProfileSettings() throws -> ProfileSettingsLoadResult {
    result
  }

  func saveDisplayName(_ displayName: String) throws -> ProfileSettingsLoadResult {
    result
  }

  func selectVoice(_ voice: VoiceProfile) throws -> ProfileSettingsLoadResult {
    result
  }

  func isVoiceAvailable(_ voice: VoiceProfile) -> Bool {
    true
  }
}

@MainActor
private final class ProfileTestVoicePreviewPlayer: VoicePreviewPlaying {
  private(set) var previewedVoices: [VoiceProfile] = []
  private(set) var stopCallCount = 0

  func previewVoice(_ voice: VoiceProfile) -> Bool {
    previewedVoices.append(voice)
    return true
  }

  func stopVoicePreview() {
    stopCallCount += 1
  }
}

@MainActor
private final class ProfileTestResetUseCase: ResetLocalDataUseCaseProtocol {
  private(set) var executeCallCount = 0

  func execute() async throws {
    executeCallCount += 1
  }
}
