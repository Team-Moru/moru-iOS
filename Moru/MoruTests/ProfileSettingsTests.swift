//
//  ProfileSettingsTests.swift
//  MoruTests
//

import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Moru

final class ProfileSettingsTests: XCTestCase {
  @MainActor
  func testDisplayNameTrimsValidGraphemeRangeAndPersistsProfile() throws {
    let profile = makeProfile()
    let profileRepository = ProfileSettingsProfileRepositoryFake(profile: profile)
    let settingsRepository = ProfileSettingsRepositoryFake(
      settings: makeSettings(profileID: profile.id, resolvedVoiceID: VoiceProfile.yuna.id),
      profileRepository: profileRepository
    )
    let useCase = makeUseCase(
      profileRepository: profileRepository,
      settingsRepository: settingsRepository
    )
    let oneGrapheme = "e\u{301}"
    let twentyGraphemes = String(repeating: oneGrapheme, count: 20)

    let trimmed = try useCase.saveDisplayName("  \(oneGrapheme)  ")
    let atLimit = try useCase.saveDisplayName(twentyGraphemes)

    XCTAssertEqual(trimmed.profile.displayName, oneGrapheme)
    XCTAssertEqual(atLimit.profile.displayName, twentyGraphemes)
    XCTAssertEqual(profileRepository.profile?.displayName, twentyGraphemes)
    XCTAssertEqual(profileRepository.profile?.createdAt, .distantPast)
    XCTAssertEqual(profileRepository.profile?.updatedAt, Self.fixedDate)
    XCTAssertEqual(profileRepository.savedProfiles.count, 2)
  }

  @MainActor
  func testDisplayNameRejectsEmptyOverLimitEmojiAndControlCharacters() throws {
    let profile = makeProfile()
    let profileRepository = ProfileSettingsProfileRepositoryFake(profile: profile)
    let settingsRepository = ProfileSettingsRepositoryFake(
      settings: makeSettings(profileID: profile.id, resolvedVoiceID: VoiceProfile.yuna.id),
      profileRepository: profileRepository
    )
    let useCase = makeUseCase(
      profileRepository: profileRepository,
      settingsRepository: settingsRepository
    )
    let overLimit = String(repeating: "e\u{301}", count: 21)

    assertInvalidDisplayName(
      "   ",
      expectedError: .empty,
      useCase: useCase
    )
    assertInvalidDisplayName(
      overLimit,
      expectedError: .tooLong,
      useCase: useCase
    )
    assertInvalidDisplayName(
      "유나🙂",
      expectedError: .containsEmoji,
      useCase: useCase
    )
    assertInvalidDisplayName(
      "유\u{0007}나",
      expectedError: .containsControlCharacter,
      useCase: useCase
    )
    assertInvalidDisplayName(
      "유나\n",
      expectedError: .containsControlCharacter,
      useCase: useCase
    )

    XCTAssertEqual(profileRepository.profile, profile)
    XCTAssertTrue(profileRepository.savedProfiles.isEmpty)
  }

  @MainActor
  func testLocalVoiceCatalogueAndUseCaseRejectUnavailableSelections() throws {
    XCTAssertEqual(VoiceProfile.localVoices, [.yuna, .sora])

    let profile = makeProfile()
    let profileRepository = ProfileSettingsProfileRepositoryFake(profile: profile)
    let settingsRepository = ProfileSettingsRepositoryFake(
      settings: makeSettings(profileID: profile.id, resolvedVoiceID: VoiceProfile.yuna.id),
      profileRepository: profileRepository
    )
    let allAvailableUseCase = makeUseCase(
      profileRepository: profileRepository,
      settingsRepository: settingsRepository,
      availableVoiceIDs: [VoiceProfile.yuna.id, VoiceProfile.sora.id]
    )
    let yunaWithModifiedFields = VoiceProfile(
      id: VoiceProfile.yuna.id,
      displayName: "다른 유나",
      localeIdentifier: "ko-KR"
    )

    XCTAssertTrue(allAvailableUseCase.isVoiceAvailable(.yuna))
    XCTAssertTrue(allAvailableUseCase.isVoiceAvailable(.sora))
    XCTAssertFalse(allAvailableUseCase.isVoiceAvailable(.moru))
    XCTAssertFalse(allAvailableUseCase.isVoiceAvailable(yunaWithModifiedFields))
    XCTAssertThrowsError(try allAvailableUseCase.selectVoice(voiceID: VoiceProfile.moru.id)) {
      XCTAssertEqual($0 as? ProfileSettingsUseCaseError, .unavailableVoice(VoiceProfile.moru.id))
    }
    XCTAssertThrowsError(try allAvailableUseCase.selectVoice(voiceID: "external.voice")) {
      XCTAssertEqual($0 as? ProfileSettingsUseCaseError, .unavailableVoice("external.voice"))
    }

    let yunaOnlyUseCase = makeUseCase(
      profileRepository: profileRepository,
      settingsRepository: settingsRepository,
      availableVoiceIDs: [VoiceProfile.yuna.id]
    )
    let viewModel = makeViewModel(useCase: yunaOnlyUseCase)

    XCTAssertFalse(viewModel.voiceSelectionButtonDidTap(.sora))
    XCTAssertEqual(viewModel.voiceErrorMessage, "이 목소리는 기기에서 사용할 수 없어요.")
    XCTAssertTrue(settingsRepository.selectedVoiceIDs.isEmpty)
    let unavailablePreviewPlayer = ProfileSettingsVoicePreviewFake()
    let unavailablePreviewViewModel = makeViewModel(
      useCase: yunaOnlyUseCase,
      previewPlayer: unavailablePreviewPlayer
    )

    unavailablePreviewViewModel.voicePreviewButtonDidTap(.sora)

    XCTAssertTrue(unavailablePreviewPlayer.previewedVoiceIDs.isEmpty)
    XCTAssertEqual(
      unavailablePreviewViewModel.voiceErrorMessage,
      "이 목소리를 미리 들을 수 없어요."
    )
    XCTAssertEqual(profileRepository.profile?.selectedVoice, .yuna)
    XCTAssertTrue(settingsRepository.selectedVoiceIDs.isEmpty)
  }

  @MainActor
  func testVoicePreviewDoesNotPersistWhileAvailableSelectionDoes() throws {
    let profile = makeProfile(selectedVoice: .yuna)
    let profileRepository = ProfileSettingsProfileRepositoryFake(profile: profile)
    let settingsRepository = ProfileSettingsRepositoryFake(
      settings: makeSettings(profileID: profile.id, resolvedVoiceID: VoiceProfile.yuna.id),
      profileRepository: profileRepository
    )
    let useCase = makeUseCase(
      profileRepository: profileRepository,
      settingsRepository: settingsRepository,
      availableVoiceIDs: [VoiceProfile.yuna.id, VoiceProfile.sora.id]
    )
    let previewPlayer = ProfileSettingsVoicePreviewFake()
    let viewModel = makeViewModel(useCase: useCase, previewPlayer: previewPlayer)

    viewModel.loadProfileSettings()
    viewModel.voicePreviewButtonDidTap(.sora)

    XCTAssertEqual(previewPlayer.previewedVoiceIDs, [VoiceProfile.sora.id])
    XCTAssertEqual(profileRepository.profile?.selectedVoice, .yuna)
    XCTAssertTrue(settingsRepository.selectedVoiceIDs.isEmpty)
    XCTAssertNil(viewModel.voiceErrorMessage)

    XCTAssertTrue(viewModel.voiceSelectionButtonDidTap(.sora))
    XCTAssertEqual(settingsRepository.selectedVoiceIDs, [VoiceProfile.sora.id])
    XCTAssertEqual(profileRepository.profile?.selectedVoice, .sora)
    XCTAssertEqual(content(from: viewModel).profile.selectedVoice, .sora)
  }
  @MainActor
  func testVoicePreviewTeardownStopsOnceWithoutPersistingSelection() throws {
    let profile = makeProfile(selectedVoice: .yuna)
    let profileRepository = ProfileSettingsProfileRepositoryFake(profile: profile)
    let settingsRepository = ProfileSettingsRepositoryFake(
      settings: makeSettings(profileID: profile.id, resolvedVoiceID: VoiceProfile.yuna.id),
      profileRepository: profileRepository
    )
    let previewPlayer = ProfileSettingsVoicePreviewFake()
    let viewModel = makeViewModel(
      useCase: makeUseCase(
        profileRepository: profileRepository,
        settingsRepository: settingsRepository,
        availableVoiceIDs: [VoiceProfile.yuna.id, VoiceProfile.sora.id]
      ),
      previewPlayer: previewPlayer
    )

    viewModel.loadProfileSettings()
    viewModel.voicePreviewButtonDidTap(.sora)
    viewModel.voiceSelectionViewDidDisappear()

    XCTAssertEqual(previewPlayer.previewedVoiceIDs, [VoiceProfile.sora.id])
    XCTAssertEqual(previewPlayer.stopCallCount, 1)
    XCTAssertEqual(profileRepository.profile?.selectedVoice, .yuna)
    XCTAssertTrue(settingsRepository.selectedVoiceIDs.isEmpty)
    XCTAssertEqual(content(from: viewModel).profile.selectedVoice, .yuna)
  }

  @MainActor
  func testVoicePreviewFailureReportsExactErrorWithoutPersisting() throws {
    let profile = makeProfile(selectedVoice: .yuna)
    let profileRepository = ProfileSettingsProfileRepositoryFake(profile: profile)
    let settingsRepository = ProfileSettingsRepositoryFake(
      settings: makeSettings(profileID: profile.id, resolvedVoiceID: VoiceProfile.yuna.id),
      profileRepository: profileRepository
    )
    let previewPlayer = ProfileSettingsVoicePreviewFake()
    previewPlayer.previewSucceeds = false
    let viewModel = makeViewModel(
      useCase: makeUseCase(
        profileRepository: profileRepository,
        settingsRepository: settingsRepository,
        availableVoiceIDs: [VoiceProfile.yuna.id, VoiceProfile.sora.id]
      ),
      previewPlayer: previewPlayer
    )

    viewModel.voicePreviewButtonDidTap(.sora)

    XCTAssertEqual(previewPlayer.previewedVoiceIDs, [VoiceProfile.sora.id])
    XCTAssertEqual(viewModel.voiceErrorMessage, "이 목소리를 미리 들을 수 없어요.")
    XCTAssertEqual(profileRepository.profile?.selectedVoice, .yuna)
    XCTAssertTrue(settingsRepository.selectedVoiceIDs.isEmpty)
  }

  @MainActor
  func testGenericFallbackNoticeAcknowledgesExactlyOnce() throws {
    let profile = makeProfile(selectedVoice: .yuna)
    let profileRepository = ProfileSettingsProfileRepositoryFake(profile: profile)
    let settingsRepository = ProfileSettingsRepositoryFake(
      settings: makeSettings(
        profileID: profile.id,
        state: .fallbackNoticePending,
        originalVoiceID: VoiceProfile.moru.id,
        resolvedVoiceID: VoiceProfile.yuna.id
      ),
      profileRepository: profileRepository
    )
    let viewModel = makeViewModel(
      useCase: makeUseCase(
        profileRepository: profileRepository,
        settingsRepository: settingsRepository
      )
    )

    viewModel.loadProfileSettings()
    XCTAssertEqual(
      viewModel.pendingVoiceNotice(in: content(from: viewModel)),
      "사용 가능한 목소리로 변경했어요"
    )

    viewModel.voiceNoticeAcknowledgeButtonDidTap()
    viewModel.voiceNoticeAcknowledgeButtonDidTap()

    XCTAssertEqual(settingsRepository.acknowledgeCallCount, 1)
    XCTAssertEqual(
      content(from: viewModel).settings.voiceMigrationState,
      .fallbackNoticeAcknowledged
    )
    XCTAssertNil(viewModel.pendingVoiceNotice(in: content(from: viewModel)))
    XCTAssertNil(viewModel.voiceErrorMessage)
  }

  @MainActor
  func testVoiceNoticeAcknowledgementFailurePreservesPendingContentAndReportsError() {
    let expectedContent = ProfileSettingsLoadResult(
      profile: makeProfile(selectedVoice: .yuna),
      settings: makeSettings(
        profileID: Self.profileID,
        state: .fallbackNoticePending,
        originalVoiceID: VoiceProfile.moru.id,
        resolvedVoiceID: VoiceProfile.yuna.id
      )
    )
    let useCase = ProfileSettingsUseCaseFake(result: expectedContent)
    useCase.acknowledgementError = .acknowledgementFailed
    let viewModel = makeViewModel(useCase: useCase)

    viewModel.loadProfileSettings()
    let contentBeforeAcknowledgement = content(from: viewModel)
    viewModel.voiceNoticeAcknowledgeButtonDidTap()

    XCTAssertEqual(useCase.acknowledgeCallCount, 1)
    XCTAssertEqual(
      viewModel.voiceErrorMessage,
      "목소리 변경 안내를 확인하지 못했어요. 다시 시도해 주세요."
    )
    XCTAssertEqual(content(from: viewModel), contentBeforeAcknowledgement)
    XCTAssertEqual(
      viewModel.pendingVoiceNotice(in: content(from: viewModel)),
      "사용 가능한 목소리로 변경했어요"
    )
  }

  @MainActor
  func testNoFallbackAndCorruptRecoveryExposeExactRetryMessages() throws {
    let cases: [(VoiceMigrationState, String)] = [
      (
        .noFallbackNoticePending,
        "사용 가능한 목소리를 찾지 못했어요. 목소리를 설치한 뒤 다시 시도해 주세요."
      ),
      (
        .corruptRecoveryPending,
        "목소리 설정을 복구해야 해요. 다시 시도해 주세요."
      ),
    ]

    for (state, expectedMessage) in cases {
      let profile = makeProfile(selectedVoice: VoiceProfile.preserving(id: "legacy.voice"))
      let profileRepository = ProfileSettingsProfileRepositoryFake(profile: profile)
      let settingsRepository = ProfileSettingsRepositoryFake(
        settings: makeSettings(
          profileID: profile.id,
          state: state,
          originalVoiceID: "legacy.voice"
        ),
        profileRepository: profileRepository
      )
      let viewModel = makeViewModel(
        useCase: makeUseCase(
          profileRepository: profileRepository,
          settingsRepository: settingsRepository
        )
      )

      viewModel.loadProfileSettings()
      let content = content(from: viewModel)

      XCTAssertEqual(viewModel.voiceRecoveryMessage(in: content), expectedMessage)
      XCTAssertTrue(viewModel.shouldOfferVoiceResolutionRetry(in: content))

      viewModel.voiceResolutionRetryButtonDidTap()

      XCTAssertEqual(settingsRepository.resolveCallCount, 2)
      XCTAssertNil(viewModel.voiceErrorMessage)
    }
  }

  @MainActor
  func testVoiceResolutionRetryFailurePreservesContentAndCanRetry() {
    let expectedContent = ProfileSettingsLoadResult(
      profile: makeProfile(selectedVoice: .yuna),
      settings: makeSettings(profileID: Self.profileID, state: .unresolved)
    )
    let useCase = ProfileSettingsUseCaseFake(result: expectedContent)
    useCase.retryError = .voiceResolutionFailed
    let viewModel = makeViewModel(useCase: useCase)

    viewModel.loadProfileSettings()
    let contentBeforeRetry = content(from: viewModel)
    viewModel.voiceResolutionRetryButtonDidTap()

    XCTAssertEqual(useCase.retryCallCount, 1)
    XCTAssertEqual(
      viewModel.voiceErrorMessage,
      "목소리 설정을 확인하지 못했어요. 다시 시도해 주세요."
    )
    XCTAssertEqual(content(from: viewModel), contentBeforeRetry)
    XCTAssertTrue(viewModel.shouldOfferVoiceResolutionRetry(in: content(from: viewModel)))

    useCase.retryError = nil
    viewModel.voiceResolutionRetryButtonDidTap()

    XCTAssertEqual(useCase.retryCallCount, 2)
    XCTAssertNil(viewModel.voiceErrorMessage)
    XCTAssertEqual(content(from: viewModel), contentBeforeRetry)
    XCTAssertTrue(viewModel.shouldOfferVoiceResolutionRetry(in: content(from: viewModel)))
  }

  @MainActor
  func testAlarmStatusProviderRefreshesStoredStatus() {
    let statusBox = ProfileAlarmStatusBox(.unavailable)
    let viewModel = makeViewModel(
      useCase: ProfileSettingsUseCaseFake(),
      alarmStatusProvider: { statusBox.value }
    )

    XCTAssertEqual(viewModel.alarmStatus, .unavailable)

    statusBox.value = .repairRequired
    viewModel.refreshAlarmStatus()

    XCTAssertEqual(viewModel.alarmStatus, .repairRequired)
  }

  @MainActor
  func testAlarmActionsForwardOnceWithoutChangingStatus() {
    var openSettingsCallCount = 0
    var repairCallCount = 0
    let permissionOffViewModel = makeViewModel(
      useCase: ProfileSettingsUseCaseFake(),
      alarmStatusProvider: { .permissionOff },
      onOpenSettings: { openSettingsCallCount += 1 },
      onRetryAlarmRepair: { repairCallCount += 1 }
    )

    permissionOffViewModel.alarmSettingsButtonDidTap()

    XCTAssertEqual(openSettingsCallCount, 1)
    XCTAssertEqual(repairCallCount, 0)
    XCTAssertEqual(permissionOffViewModel.alarmStatus, .permissionOff)

    let repairRequiredViewModel = makeViewModel(
      useCase: ProfileSettingsUseCaseFake(),
      alarmStatusProvider: { .repairRequired },
      onOpenSettings: { openSettingsCallCount += 1 },
      onRetryAlarmRepair: { repairCallCount += 1 }
    )

    repairRequiredViewModel.alarmRepairRetryButtonDidTap()

    XCTAssertEqual(openSettingsCallCount, 1)
    XCTAssertEqual(repairCallCount, 1)
    XCTAssertEqual(repairRequiredViewModel.alarmStatus, .repairRequired)
  }

  @MainActor
  func testCommittedCommandsReturnSnapshotsWhenFutureReadsFail() throws {
    let displayProfile = makeProfile()
    let displayProfileRepository = ProfileSettingsProfileRepositoryFake(profile: displayProfile)
    let displaySettingsRepository = ProfileSettingsRepositoryFake(
      settings: makeSettings(
        profileID: displayProfile.id,
        resolvedVoiceID: VoiceProfile.yuna.id
      ),
      profileRepository: displayProfileRepository
    )
    displayProfileRepository.failReadsAfterSave = true

    let displayResult = try makeUseCase(
      profileRepository: displayProfileRepository,
      settingsRepository: displaySettingsRepository
    ).saveDisplayName("새 이름")

    XCTAssertEqual(
      displayResult.profile,
      try XCTUnwrap(displayProfileRepository.profile)
    )
    XCTAssertEqual(displayResult.settings, displaySettingsRepository.settings)

    let voiceProfile = makeProfile()
    let voiceProfileRepository = ProfileSettingsProfileRepositoryFake(profile: voiceProfile)
    let voiceSettingsRepository = ProfileSettingsRepositoryFake(
      settings: makeSettings(
        profileID: voiceProfile.id,
        resolvedVoiceID: VoiceProfile.yuna.id
      ),
      profileRepository: voiceProfileRepository
    )
    voiceProfileRepository.failReadsAfterSave = true

    let voiceResult = try makeUseCase(
      profileRepository: voiceProfileRepository,
      settingsRepository: voiceSettingsRepository,
      availableVoiceIDs: [VoiceProfile.yuna.id, VoiceProfile.sora.id]
    ).selectVoice(voiceID: VoiceProfile.sora.id)

    XCTAssertEqual(
      voiceResult.profile,
      try XCTUnwrap(voiceProfileRepository.profile)
    )
    XCTAssertEqual(voiceResult.settings, voiceSettingsRepository.settings)

    let acknowledgementProfile = makeProfile()
    let acknowledgementProfileRepository = ProfileSettingsProfileRepositoryFake(
      profile: acknowledgementProfile
    )
    let acknowledgementSettingsRepository = ProfileSettingsRepositoryFake(
      settings: makeSettings(
        profileID: acknowledgementProfile.id,
        state: .fallbackNoticePending,
        originalVoiceID: VoiceProfile.moru.id,
        resolvedVoiceID: VoiceProfile.yuna.id
      ),
      profileRepository: acknowledgementProfileRepository
    )
    acknowledgementSettingsRepository.failReadsAfterAcknowledgement = true

    let acknowledgementResult = try makeUseCase(
      profileRepository: acknowledgementProfileRepository,
      settingsRepository: acknowledgementSettingsRepository
    ).acknowledgeVoiceNotice()

    XCTAssertEqual(
      acknowledgementResult.profile,
      try XCTUnwrap(acknowledgementProfileRepository.profile)
    )
    XCTAssertEqual(
      acknowledgementResult.settings,
      acknowledgementSettingsRepository.settings
    )
  }

  @MainActor
  func testSettingsUnavailableIsTypedAndPreventsDisplayNameWrite() throws {
    let profile = makeProfile()
    let profileRepository = ProfileSettingsProfileRepositoryFake(profile: profile)
    let settingsRepository = ProfileSettingsRepositoryFake(
      settings: makeSettings(profileID: profile.id, resolvedVoiceID: VoiceProfile.yuna.id),
      profileRepository: profileRepository
    )
    settingsRepository.returnsNilOnFetch = true
    let useCase = makeUseCase(
      profileRepository: profileRepository,
      settingsRepository: settingsRepository
    )

    XCTAssertThrowsError(try useCase.saveDisplayName("새 이름")) {
      XCTAssertEqual($0 as? ProfileSettingsUseCaseError, .settingsUnavailable)
    }
    XCTAssertTrue(profileRepository.savedProfiles.isEmpty)
  }
  func testOwnedProfileSourceTreeContainsNoForbiddenSurfaceTokens() throws {
    // Supplemental audit of owned Profile sources.
    // Routes outside this tree need separate coverage.
    let testFileURL = URL(fileURLWithPath: #filePath)
    let profileDirectoryURL = testFileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "Moru/Features/Profile")
    guard let enumerator = FileManager.default.enumerator(
      at: profileDirectoryURL,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else {
      return XCTFail("Expected the owned Profile source tree.")
    }

    let source = try enumerator
      .compactMap { $0 as? URL }
      .filter { $0.pathExtension == "swift" }
      .sorted { $0.path < $1.path }
      .map { try String(contentsOf: $0, encoding: .utf8) }
      .joined(separator: "\n")
    let forbiddenTokens = [
      "로그인",
      "로그아웃",
      "회원 탈퇴",
      "이메일",
      "구독",
      "소셜",
      "인증",
      "결제",
      "프리미엄",
      "진동",
      "socialLogin",
      "SocialLogin",
      "social",
      "Social",
      "account",
      "Account",
      "login",
      "Login",
      "logout",
      "Logout",
      "email",
      "Email",
      "subscription",
      "Subscription",
      "authentication",
      "Authentication",
      "auth",
      "Auth",
      "signIn",
      "SignIn",
      "signOut",
      "SignOut",
      "paywall",
      "Paywall",
      "premium",
      "Premium",
      "isPro",
      "PRO",
      "vibration",
      "Vibration",
      "haptic",
      "Haptic",
    ]

    for forbiddenToken in forbiddenTokens {
      XCTAssertFalse(
        source.contains(forbiddenToken),
        "Owned Profile source tree contains forbidden token: \(forbiddenToken)"
      )
    }
  }

  @MainActor
  func testProfileSettingsRenderInNativeSurface() throws {
    let profile = makeProfile(selectedVoice: .yuna)
    let profileRepository = ProfileSettingsProfileRepositoryFake(profile: profile)
    let settingsRepository = ProfileSettingsRepositoryFake(
      settings: makeSettings(profileID: profile.id, resolvedVoiceID: VoiceProfile.yuna.id),
      profileRepository: profileRepository
    )
    let resetPerformer = ProfileSettingsResetPerformerFake(
      availability: .blockedByAlarmReset
    )
    let viewModel = makeViewModel(
      useCase: makeUseCase(
        profileRepository: profileRepository,
        settingsRepository: settingsRepository
      ),
      resetPerformer: resetPerformer,
      alarmStatusProvider: { .unavailable }
    )

    viewModel.loadProfileSettings()
    let loadedContent = content(from: viewModel)

    XCTAssertEqual(loadedContent.profile.id, profile.id)
    XCTAssertEqual(loadedContent.profile.displayName, profile.displayName)
    XCTAssertEqual(loadedContent.profile.selectedVoice, VoiceProfile.yuna)
    XCTAssertEqual(
      loadedContent.profile.updatedAt,
      settingsRepository.settings.migrationUpdatedAt
    )
    XCTAssertEqual(loadedContent.settings, settingsRepository.settings)
    XCTAssertEqual(ProfileView.currentVoiceName(in: loadedContent), VoiceProfile.yuna.displayName)
    XCTAssertEqual(viewModel.alarmStatus, .unavailable)
    XCTAssertEqual(
      ProfileView.alarmStatusMessage(for: viewModel.alarmStatus),
      "알람 상태를 확인할 수 없어요"
    )
    XCTAssertFalse(viewModel.isResetAvailable)
    XCTAssertEqual(
      viewModel.resetAvailabilityMessage,
      "초기화 작업을 마친 뒤 다시 시도해 주세요"
    )
    XCTAssertEqual(
      viewModel.resetAccessibilityHint,
      "초기화 작업을 마친 뒤 다시 시도해 주세요 "
        + "초기화 버튼을 사용할 수 없어요."
    )
    XCTAssertEqual(ProfileView.rootAccessibilityIdentifier, "profile.root")
    XCTAssertEqual(ProfileView.rootAccessibilityLabel, "마이 프로필과 설정")
    XCTAssertEqual(ProfileView.localResetDescription, "이 기기에 저장된 로컬 데이터를 초기화합니다.")

    let bounds = CGRect(x: 0, y: 0, width: 393, height: 1_200)
    let windowScene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    )
    let hostingController = UIHostingController(rootView: ProfileView(viewModel: viewModel))
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
    let screenshotURL = URL(fileURLWithPath: "/tmp/moru-g003-profile.png")
    try pngData.write(to: screenshotURL, options: .atomic)

    XCTAssertGreaterThan(pngData.count, 1_000)
    let renderedImage = try XCTUnwrap(image.cgImage)
    let pixelData = try XCTUnwrap(renderedImage.dataProvider?.data as Data?)
    let bytesPerPixel = renderedImage.bitsPerPixel / renderedImage.bitsPerComponent
    let hasNonuniformPixels = pixelData.withUnsafeBytes { rawBuffer in
      guard bytesPerPixel > 0,
            pixelData.count >= bytesPerPixel,
            let bytes = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return false
      }

      let firstPixel = (0..<bytesPerPixel).map { bytes[$0] }

      for row in 0..<renderedImage.height {
        for column in 0..<renderedImage.width {
          let offset = row * renderedImage.bytesPerRow + column * bytesPerPixel

          if (0..<bytesPerPixel).contains(where: { bytes[offset + $0] != firstPixel[$0] }) {
            return true
          }
        }
      }

      return false
    }

    XCTAssertTrue(
      hasNonuniformPixels,
      "Expected the Profile screenshot to contain nonuniform pixels."
    )
  }

  @MainActor
  func testResetConfirmationNeverResetsWhileActiveRoutineOrAlarmRepairBlocksIt() async {
    let cases: [(LocalResetAvailability, String)] = [
      (.blockedByActiveRoutine, "루틴이 끝난 후 초기화해 주세요"),
      (.blockedByAlarmRepair, "알람 상태를 먼저 복구해 주세요"),
      (.blockedByAlarmReset, "초기화 작업을 마친 뒤 다시 시도해 주세요"),
    ]

    for (availability, expectedMessage) in cases {
      let resetPerformer = ProfileSettingsResetPerformerFake(availability: availability)
      let viewModel = makeViewModel(
        useCase: ProfileSettingsUseCaseFake(),
        resetPerformer: resetPerformer
      )

      XCTAssertFalse(viewModel.resetButtonDidTap())
      XCTAssertEqual(viewModel.resetStatusMessage, expectedMessage)
      XCTAssertEqual(
        viewModel.resetAccessibilityHint,
        "\(expectedMessage) 초기화 버튼을 사용할 수 없어요."
      )

      await viewModel.resetConfirmationButtonDidTap()

      XCTAssertEqual(resetPerformer.resetCallCount, 0)
      XCTAssertEqual(viewModel.resetStatusMessage, expectedMessage)
      XCTAssertFalse(viewModel.didResetSucceed)
      XCTAssertFalse(viewModel.isResetInProgress)
    }
  }

  @MainActor
  func testAvailableResetCallsPerformerOnceAndSurfacesSuccessOrFailure() async {
    let successfulReset = ProfileSettingsResetPerformerFake(availability: .available)
    let successfulViewModel = makeViewModel(
      useCase: ProfileSettingsUseCaseFake(),
      resetPerformer: successfulReset
    )

    XCTAssertTrue(successfulViewModel.resetButtonDidTap())
    await successfulViewModel.resetConfirmationButtonDidTap()

    XCTAssertEqual(successfulReset.resetCallCount, 1)
    XCTAssertTrue(successfulViewModel.didResetSucceed)
    XCTAssertEqual(successfulViewModel.resetStatusMessage, "로컬 데이터를 초기화했어요.")
    XCTAssertFalse(successfulViewModel.isResetInProgress)

    let failedReset = ProfileSettingsResetPerformerFake(
      availability: .available,
      shouldFail: true
    )
    let failedViewModel = makeViewModel(
      useCase: ProfileSettingsUseCaseFake(),
      resetPerformer: failedReset
    )

    XCTAssertTrue(failedViewModel.resetButtonDidTap())
    await failedViewModel.resetConfirmationButtonDidTap()

    XCTAssertEqual(failedReset.resetCallCount, 1)
    XCTAssertFalse(failedViewModel.didResetSucceed)
    XCTAssertEqual(failedViewModel.resetStatusMessage, "초기화하지 못했어요. 다시 시도해 주세요.")
    XCTAssertFalse(failedViewModel.isResetInProgress)
  }

  @MainActor
  func testDuplicateResetConfirmationOnlyPerformsOneDestructiveReset() async {
    let resetPerformer = ProfileSettingsSuspendingResetPerformerFake()
    let viewModel = makeViewModel(
      useCase: ProfileSettingsUseCaseFake(),
      resetPerformer: resetPerformer
    )
    let initialReset = Task {
      await viewModel.resetConfirmationButtonDidTap()
    }

    await resetPerformer.waitForResetToStart()

    XCTAssertTrue(viewModel.isResetInProgress)
    XCTAssertEqual(resetPerformer.resetCallCount, 1)

    await viewModel.resetConfirmationButtonDidTap()

    XCTAssertTrue(viewModel.isResetInProgress)
    XCTAssertEqual(resetPerformer.resetCallCount, 1)

    resetPerformer.completeReset()
    await initialReset.value

    XCTAssertFalse(viewModel.isResetInProgress)
    XCTAssertTrue(viewModel.didResetSucceed)
    XCTAssertEqual(viewModel.resetStatusMessage, "로컬 데이터를 초기화했어요.")
    XCTAssertEqual(resetPerformer.resetCallCount, 1)
  }

  @MainActor
  private func assertInvalidDisplayName(
    _ name: String,
    expectedError: ProfileDisplayNameValidationError,
    useCase: ProfileSettingsUseCase,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(try useCase.saveDisplayName(name), file: file, line: line) {
      XCTAssertEqual(
        $0 as? ProfileSettingsUseCaseError,
        .invalidDisplayName(expectedError),
        file: file,
        line: line
      )
    }
  }

  @MainActor
  private func makeUseCase(
    profileRepository: ProfileSettingsProfileRepositoryFake,
    settingsRepository: ProfileSettingsRepositoryFake,
    availableVoiceIDs: Set<String> = [VoiceProfile.yuna.id]
  ) -> ProfileSettingsUseCase {
    ProfileSettingsUseCase(
      localProfileRepository: profileRepository,
      localSettingsRepository: settingsRepository,
      voiceAvailabilityProbe: ProfileSettingsVoiceAvailabilityProbe(
        availableVoiceIDs: availableVoiceIDs
      ),
      now: { Self.fixedDate }
    )
  }

  @MainActor
  private func makeViewModel(
    useCase: any ProfileSettingsUseCaseProtocol,
    previewPlayer: ProfileSettingsVoicePreviewFake? = nil,
    resetPerformer: (any ProfileLocalResetPerforming)? = nil,
    alarmStatusProvider: @escaping @MainActor () -> ProfileAlarmStatus = { .configured },
    onOpenSettings: @escaping @MainActor () -> Void = {},
    onRetryAlarmRepair: @escaping @MainActor () -> Void = {}
  ) -> ProfileViewModel {
    let resolvedPreviewPlayer = previewPlayer ?? ProfileSettingsVoicePreviewFake()
    let resolvedResetPerformer = resetPerformer ?? ProfileSettingsResetPerformerFake(
      availability: .available
    )

    return ProfileViewModel(
      profileSettingsUseCase: useCase,
      voicePreviewPlayer: resolvedPreviewPlayer,
      alarmStatusProvider: alarmStatusProvider,
      resetPerformer: resolvedResetPerformer,
      onOpenSettings: onOpenSettings,
      onRetryAlarmRepair: onRetryAlarmRepair
    )
  }

  @MainActor
  private func content(
    from viewModel: ProfileViewModel,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> ProfileSettingsLoadResult {
    guard case .content(let content) = viewModel.state else {
      XCTFail("Expected profile settings content.", file: file, line: line)
      fatalError("Profile settings content is required for this assertion.")
    }

    return content
  }

  private func makeProfile(
    selectedVoice: VoiceProfile = .yuna
  ) -> LocalProfile {
    LocalProfile(
      id: Self.profileID,
      displayName: "다인",
      selectedVoice: selectedVoice,
      createdAt: .distantPast,
      updatedAt: .distantPast
    )
  }

  private func makeSettings(
    profileID: UUID,
    state: VoiceMigrationState = .resolved,
    originalVoiceID: String? = nil,
    resolvedVoiceID: String? = nil
  ) -> LocalSettingsSnapshot {
    let schemaMigrationMarker: SchemaMigrationMarker
    switch state {
    case .unresolved,
         .noFallbackNoticePending,
         .noFallbackNoticeAcknowledged,
         .corruptRecoveryPending:
      schemaMigrationMarker = .v2Unresolved
    case .resolved, .fallbackNoticePending, .fallbackNoticeAcknowledged:
      schemaMigrationMarker = .v2Resolved
    }

    return LocalSettingsSnapshot(
      id: profileID,
      profileID: profileID,
      voiceMigrationState: state,
      originalVoiceID: originalVoiceID,
      resolvedVoiceID: resolvedVoiceID,
      migrationUpdatedAt: Self.fixedDate,
      schemaMigrationMarker: schemaMigrationMarker
    )
  }


  private static let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  private static let fixedDate = Date(timeIntervalSince1970: 1_752_854_400)
}

@MainActor
private final class ProfileSettingsProfileRepositoryFake: LocalProfileRepository {
  private(set) var profile: LocalProfile?
  private(set) var savedProfiles: [LocalProfile] = []
  var failReadsAfterSave = false
  private var readsFail = false

  init(profile: LocalProfile?) {
    self.profile = profile
  }

  func fetchProfile() throws -> LocalProfile? {
    guard !readsFail else {
      throw ProfileSettingsFakeError.postCommitReadFailed
    }

    return profile
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
    savedProfiles.append(profile)

    if failReadsAfterSave {
      readsFail = true
    }
  }

  func deleteProfile() throws {
    profile = nil
  }
}

@MainActor
private final class ProfileSettingsRepositoryFake: LocalSettingsRepository {
  private let profileRepository: ProfileSettingsProfileRepositoryFake
  private(set) var settings: LocalSettingsSnapshot
  private(set) var resolveCallCount = 0
  private(set) var acknowledgeCallCount = 0
  private(set) var selectedVoiceIDs: [String] = []
  var returnsNilOnFetch = false
  var failReadsAfterAcknowledgement = false
  private var readsFail = false

  init(
    settings: LocalSettingsSnapshot,
    profileRepository: ProfileSettingsProfileRepositoryFake
  ) {
    self.settings = settings
    self.profileRepository = profileRepository
  }

  func fetchSettings(profileID: UUID) throws -> LocalSettingsSnapshot? {
    guard !readsFail else {
      throw ProfileSettingsFakeError.postCommitReadFailed
    }

    guard profileID == settings.profileID else {
      return nil
    }

    return returnsNilOnFetch ? nil : settings
  }

  func resolveVoiceSettings(profileID: UUID) throws -> LocalSettingsSnapshot {
    guard profileID == settings.profileID else {
      throw ProfileSettingsFakeError.unknownProfile
    }

    resolveCallCount += 1
    return settings
  }

  func acknowledgeVoiceNotice(profileID: UUID) throws {
    guard profileID == settings.profileID,
          settings.voiceMigrationState == .fallbackNoticePending else {
      throw ProfileSettingsFakeError.noticeNotPending
    }

    acknowledgeCallCount += 1
    settings = replacingSettings(
      voiceMigrationState: .fallbackNoticeAcknowledged,
      originalVoiceID: settings.originalVoiceID,
      resolvedVoiceID: settings.resolvedVoiceID,
      schemaMigrationMarker: .v2Resolved
    )

    if failReadsAfterAcknowledgement {
      readsFail = true
    }
  }

  func selectVoice(profileID: UUID, voiceID: String) throws -> LocalSettingsSnapshot {
    guard profileID == settings.profileID,
          let voice = VoiceProfile.catalogueVoice(id: voiceID),
          var profile = try profileRepository.fetchProfile(),
          profile.id == profileID else {
      throw ProfileSettingsFakeError.invalidVoiceSelection
    }

    selectedVoiceIDs.append(voiceID)
    profile.selectedVoice = voice
    profile.updatedAt = settings.migrationUpdatedAt ?? profile.updatedAt
    try profileRepository.saveProfile(profile)
    settings = replacingSettings(
      voiceMigrationState: .resolved,
      originalVoiceID: nil,
      resolvedVoiceID: voiceID,
      schemaMigrationMarker: .v2Resolved
    )
    return settings
  }

  private func replacingSettings(
    voiceMigrationState: VoiceMigrationState,
    originalVoiceID: String? = nil,
    resolvedVoiceID: String? = nil,
    schemaMigrationMarker: SchemaMigrationMarker
  ) -> LocalSettingsSnapshot {
    LocalSettingsSnapshot(
      id: settings.id,
      profileID: settings.profileID,
      voiceMigrationState: voiceMigrationState,
      originalVoiceID: originalVoiceID,
      resolvedVoiceID: resolvedVoiceID,
      migrationUpdatedAt: settings.migrationUpdatedAt,
      schemaMigrationMarker: schemaMigrationMarker
    )
  }
}

private struct ProfileSettingsVoiceAvailabilityProbe: VoiceAvailabilityProbing {
  let availableVoiceIDs: Set<String>

  func isAvailable(_ voice: VoiceProfile) -> Bool {
    availableVoiceIDs.contains(voice.id)
  }
}

@MainActor
private final class ProfileSettingsUseCaseFake: ProfileSettingsUseCaseProtocol {
  private let result: ProfileSettingsLoadResult
  private(set) var acknowledgeCallCount = 0
  private(set) var retryCallCount = 0
  var acknowledgementError: ProfileSettingsFakeError?
  var retryError: ProfileSettingsFakeError?

  init(result: ProfileSettingsLoadResult? = nil) {
    if let result {
      self.result = result
      return
    }

    let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    self.result = ProfileSettingsLoadResult(
      profile: LocalProfile(
        id: profileID,
        displayName: "다인",
        selectedVoice: .yuna,
        createdAt: .distantPast,
        updatedAt: .distantPast
      ),
      settings: LocalSettingsSnapshot(
        id: profileID,
        profileID: profileID,
        voiceMigrationState: .resolved,
        originalVoiceID: nil,
        resolvedVoiceID: VoiceProfile.yuna.id,
        migrationUpdatedAt: nil,
        schemaMigrationMarker: .v2Resolved
      )
    )
  }

  func loadProfileSettings() throws -> ProfileSettingsLoadResult {
    result
  }

  func saveDisplayName(_ displayName: String) throws -> ProfileSettingsLoadResult {
    result
  }

  func selectVoice(voiceID: String) throws -> ProfileSettingsLoadResult {
    result
  }

  func acknowledgeVoiceNotice() throws -> ProfileSettingsLoadResult {
    acknowledgeCallCount += 1

    if let acknowledgementError {
      throw acknowledgementError
    }

    return result
  }

  func retryVoiceResolution() throws -> ProfileSettingsLoadResult {
    retryCallCount += 1

    if let retryError {
      throw retryError
    }

    return result
  }

  func isVoiceAvailable(_ voice: VoiceProfile) -> Bool {
    VoiceProfile.catalogueVoice(id: voice.id) == voice
  }
}

@MainActor
private final class ProfileAlarmStatusBox {
  var value: ProfileAlarmStatus

  init(_ value: ProfileAlarmStatus) {
    self.value = value
  }
}

@MainActor
private final class ProfileSettingsVoicePreviewFake: VoicePreviewPlaying {
  private(set) var previewedVoiceIDs: [String] = []
  private(set) var stopCallCount = 0
  var previewSucceeds = true

  @discardableResult
  func previewVoice(_ voice: VoiceProfile) -> Bool {
    previewedVoiceIDs.append(voice.id)
    return previewSucceeds
  }

  func stopVoicePreview() {
    stopCallCount += 1
  }
}

@MainActor
private final class ProfileSettingsResetPerformerFake: ProfileLocalResetPerforming {
  private let resetAvailability: LocalResetAvailability
  private let shouldFail: Bool
  private(set) var resetCallCount = 0

  init(availability: LocalResetAvailability, shouldFail: Bool = false) {
    resetAvailability = availability
    self.shouldFail = shouldFail
  }

  func availability() -> LocalResetAvailability {
    resetAvailability
  }

  func reset() async throws {
    resetCallCount += 1

    if shouldFail {
      throw ProfileSettingsFakeError.resetFailed
    }
  }
}

@MainActor
private final class ProfileSettingsSuspendingResetPerformerFake: ProfileLocalResetPerforming {
  private var resetContinuation: CheckedContinuation<Void, Never>?
  private var resetStartContinuation: CheckedContinuation<Void, Never>?
  private(set) var resetCallCount = 0

  func availability() -> LocalResetAvailability {
    .available
  }

  func reset() async throws {
    resetCallCount += 1
    resetStartContinuation?.resume()
    resetStartContinuation = nil

    await withCheckedContinuation { continuation in
      resetContinuation = continuation
    }
  }

  func waitForResetToStart() async {
    guard resetCallCount == 0 else {
      return
    }

    await withCheckedContinuation { continuation in
      resetStartContinuation = continuation
    }
  }

  func completeReset() {
    guard let resetContinuation else {
      fatalError("Expected a suspended reset.")
    }

    self.resetContinuation = nil
    resetContinuation.resume()
  }
}

private enum ProfileSettingsFakeError: Error {
  case unknownProfile
  case noticeNotPending
  case invalidVoiceSelection
  case acknowledgementFailed
  case voiceResolutionFailed
  case resetFailed
  case postCommitReadFailed
}
