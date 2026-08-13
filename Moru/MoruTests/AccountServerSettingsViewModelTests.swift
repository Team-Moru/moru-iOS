//
//  AccountServerSettingsViewModelTests.swift
//  MoruTests
//

import XCTest

@testable import Moru

final class AccountServerSettingsViewModelTests: XCTestCase {
  @MainActor
  func testLoadPublishesIndependentAccountResourcesWithoutSubscriptionRequest()
    async {
    let service = AccountServerSettingsRemoteStub(
      profile: .success(accountSettingsProfile()),
      streak: .failure(.unavailable),
      voices: .success([])
    )
    let viewModel = AccountServerSettingsViewModel(
      remoteService: service
    )

    await viewModel.load(memberID: 98)

    XCTAssertEqual(
      viewModel.profileState,
      .content(accountSettingsProfile())
    )
    XCTAssertEqual(viewModel.streakState, .failed(previous: nil))
    XCTAssertEqual(viewModel.voiceState, .empty)
    XCTAssertEqual(viewModel.selectedTTSID, 1)
    let calls = await service.calls
    XCTAssertEqual(calls.count, 3)
    XCTAssertTrue(calls.contains(.profile(98)))
    XCTAssertTrue(calls.contains(.streak(98)))
    XCTAssertTrue(calls.contains(.voices(98)))
  }

  @MainActor
  func testFailedRefreshKeepsPreviousValuesWithoutCallingItFree()
    async {
    let service = AccountServerSequencedRemoteStub(
      firstProfile: accountSettingsProfile(),
      firstStreak: accountSettingsStreak(),
      firstVoices: [accountSettingsVoice(ttsID: 1)]
    )
    let viewModel = AccountServerSettingsViewModel(
      remoteService: service
    )

    await viewModel.load(memberID: 98)
    await viewModel.load(memberID: 98)

    XCTAssertEqual(
      viewModel.profileState,
      .failed(previous: accountSettingsProfile())
    )
    XCTAssertEqual(
      viewModel.streakState,
      .failed(previous: accountSettingsStreak())
    )
    XCTAssertEqual(
      viewModel.voiceState,
      .failed(previous: [accountSettingsVoice(ttsID: 1)])
    )
    XCTAssertEqual(viewModel.selectedTTSID, 1)
  }

  @MainActor
  func testProOnlyVoicesAreExcludedFromSelection() async {
    let freeVoice = accountSettingsVoice(ttsID: 1)
    let proVoice = accountSettingsVoice(ttsID: 2, isProOnly: true)
    let service = AccountServerSettingsRemoteStub(
      profile: .success(accountSettingsProfile()),
      streak: .success(accountSettingsStreak()),
      voices: .success([freeVoice, proVoice])
    )
    let viewModel = AccountServerSettingsViewModel(
      remoteService: service
    )
    await viewModel.load(memberID: 98)

    XCTAssertEqual(viewModel.voiceState, .content([freeVoice]))

    await viewModel.selectVoice(proVoice, memberID: 98)

    XCTAssertEqual(viewModel.selectedTTSID, 1)
    let updateCallCount = await service.updateCallCount
    XCTAssertEqual(updateCallCount, 0)
  }

  @MainActor
  func testFreeVoiceSelectionUsesTTSPatch() async {
    let voice = accountSettingsVoice(ttsID: 2)
    let service = AccountServerSettingsRemoteStub(
      profile: .success(accountSettingsProfile()),
      streak: .success(accountSettingsStreak()),
      voices: .success([voice])
    )
    var invalidatedMemberIDs: [Int64] = []
    let viewModel = AccountServerSettingsViewModel(
      remoteService: service,
      onServerVoiceSelectionDidSucceed: { memberID in
        invalidatedMemberIDs.append(memberID)
      }
    )
    await viewModel.load(memberID: 98)

    await viewModel.selectVoice(voice, memberID: 98)

    XCTAssertEqual(viewModel.selectedTTSID, 2)
    XCTAssertEqual(
      viewModel.latestSelection,
      ServerTTSSelection(
        memberID: 98,
        ttsID: 2,
        voiceCode: "VOICE_2",
        displayName: "서버 음성 2"
      )
    )
    let calls = await service.calls
    XCTAssertTrue(calls.contains(.update(ttsID: 2, memberID: 98)))
    XCTAssertEqual(invalidatedMemberIDs, [98])
  }

  @MainActor
  func testVoiceSelectionIsPessimisticAndPreservesOldValueOnFailure()
    async {
    let voice = accountSettingsVoice(ttsID: 2)
    let service = AccountServerDeferredUpdateRemoteStub(voice: voice)
    var invalidatedMemberIDs: [Int64] = []
    let viewModel = AccountServerSettingsViewModel(
      remoteService: service,
      onServerVoiceSelectionDidSucceed: { memberID in
        invalidatedMemberIDs.append(memberID)
      }
    )
    await viewModel.load(memberID: 98)

    let update = Task {
      await viewModel.selectVoice(voice, memberID: 98)
    }
    await service.waitUntilUpdateRequested()
    await viewModel.load(memberID: 98)

    XCTAssertEqual(viewModel.selectedTTSID, 1)
    XCTAssertTrue(viewModel.isUpdatingVoice)
    XCTAssertEqual(viewModel.updatingTTSID, 2)

    await service.resumeUpdate(throwing: .unavailable)
    await update.value

    XCTAssertEqual(viewModel.selectedTTSID, 1)
    XCTAssertFalse(viewModel.isUpdatingVoice)
    XCTAssertNil(viewModel.updatingTTSID)
    XCTAssertEqual(
      viewModel.voiceUpdateErrorMessage,
      "서버 음성을 변경하지 못했어요. 기존 선택은 유지됩니다."
    )
    XCTAssertTrue(invalidatedMemberIDs.isEmpty)
  }

  @MainActor
  func testAccountChangeNeverPublishesPreviousAccountValues() async {
    let firstProfile = accountSettingsProfile(memberID: 98)
    let service = AccountServerAccountChangeRemoteStub(
      firstProfile: firstProfile
    )
    let viewModel = AccountServerSettingsViewModel(
      remoteService: service
    )
    await viewModel.load(memberID: 98)

    let secondLoad = Task {
      await viewModel.load(memberID: 99)
    }
    await service.waitUntilSecondProfileRequested()

    XCTAssertEqual(viewModel.profileState, .loading(previous: nil))
    XCTAssertEqual(viewModel.streakState, .loading(previous: nil))
    XCTAssertEqual(viewModel.voiceState, .loading(previous: nil))
    XCTAssertNil(viewModel.selectedTTSID)

    await service.resumeSecondProfile(throwing: .unavailable)
    await secondLoad.value

    XCTAssertEqual(viewModel.profileState, .failed(previous: nil))
    XCTAssertEqual(viewModel.streakState, .failed(previous: nil))
    XCTAssertEqual(viewModel.voiceState, .failed(previous: nil))
    XCTAssertNil(viewModel.selectedTTSID)
  }
}

private enum AccountServerSettingsCall: Equatable, Sendable {
  case profile(Int64)
  case streak(Int64)
  case voices(Int64)
  case update(ttsID: Int64, memberID: Int64)
}

private enum AccountServerSettingsTestError: Error, Sendable {
  case unavailable
}

private actor AccountServerSettingsRemoteStub:
  AccountServerRemoteServing {
  private let profileResult:
    Result<ServerAccountProfile, AccountServerSettingsTestError>
  private let streakResult:
    Result<ServerAccountStreak, AccountServerSettingsTestError>
  private let voiceResult:
    Result<[ServerTTSVoice], AccountServerSettingsTestError>
  private(set) var calls: [AccountServerSettingsCall] = []

  init(
    profile:
      Result<ServerAccountProfile, AccountServerSettingsTestError>,
    streak:
      Result<ServerAccountStreak, AccountServerSettingsTestError>,
    voices:
      Result<[ServerTTSVoice], AccountServerSettingsTestError>
  ) {
    profileResult = profile
    streakResult = streak
    voiceResult = voices
  }

  func fetchProfile(
    memberID: Int64
  ) async throws -> ServerAccountProfile {
    calls.append(.profile(memberID))
    return try profileResult.get()
  }

  func fetchStreak(
    memberID: Int64
  ) async throws -> ServerAccountStreak {
    calls.append(.streak(memberID))
    return try streakResult.get()
  }

  func fetchVoices(
    memberID: Int64
  ) async throws -> [ServerTTSVoice] {
    calls.append(.voices(memberID))
    return try voiceResult.get()
  }

  func updateTTS(
    ttsID: Int64,
    memberID: Int64
  ) async throws -> ServerTTSSelection {
    calls.append(.update(ttsID: ttsID, memberID: memberID))
    return ServerTTSSelection(
      memberID: memberID,
      ttsID: ttsID,
      voiceCode: "VOICE_\(ttsID)",
      displayName: "서버 음성 \(ttsID)"
    )
  }

  var updateCallCount: Int {
    calls.filter {
      if case .update = $0 {
        return true
      }
      return false
    }.count
  }
}

private actor AccountServerSequencedRemoteStub:
  AccountServerRemoteServing {
  private let firstProfile: ServerAccountProfile
  private let firstStreak: ServerAccountStreak
  private let firstVoices: [ServerTTSVoice]
  private var profileCallCount = 0
  private var streakCallCount = 0
  private var voiceCallCount = 0

  init(
    firstProfile: ServerAccountProfile,
    firstStreak: ServerAccountStreak,
    firstVoices: [ServerTTSVoice]
  ) {
    self.firstProfile = firstProfile
    self.firstStreak = firstStreak
    self.firstVoices = firstVoices
  }

  func fetchProfile(
    memberID: Int64
  ) async throws -> ServerAccountProfile {
    profileCallCount += 1
    guard profileCallCount == 1 else {
      throw AccountServerSettingsTestError.unavailable
    }
    return firstProfile
  }

  func fetchStreak(
    memberID: Int64
  ) async throws -> ServerAccountStreak {
    streakCallCount += 1
    guard streakCallCount == 1 else {
      throw AccountServerSettingsTestError.unavailable
    }
    return firstStreak
  }

  func fetchVoices(
    memberID: Int64
  ) async throws -> [ServerTTSVoice] {
    voiceCallCount += 1
    guard voiceCallCount == 1 else {
      throw AccountServerSettingsTestError.unavailable
    }
    return firstVoices
  }

  func updateTTS(
    ttsID: Int64,
    memberID: Int64
  ) async throws -> ServerTTSSelection {
    throw AccountServerSettingsTestError.unavailable
  }

}

private actor AccountServerDeferredUpdateRemoteStub:
  AccountServerRemoteServing {
  private let voice: ServerTTSVoice
  private var updateContinuation:
    CheckedContinuation<ServerTTSSelection, Error>?
  private var didRequestUpdate = false

  init(voice: ServerTTSVoice) {
    self.voice = voice
  }

  func fetchProfile(
    memberID: Int64
  ) async throws -> ServerAccountProfile {
    accountSettingsProfile()
  }

  func fetchStreak(
    memberID: Int64
  ) async throws -> ServerAccountStreak {
    accountSettingsStreak()
  }

  func fetchVoices(
    memberID: Int64
  ) async throws -> [ServerTTSVoice] {
    [voice]
  }

  func updateTTS(
    ttsID: Int64,
    memberID: Int64
  ) async throws -> ServerTTSSelection {
    didRequestUpdate = true
    return try await withCheckedThrowingContinuation {
      updateContinuation = $0
    }
  }

  func waitUntilUpdateRequested() async {
    while !didRequestUpdate {
      await Task.yield()
    }
  }

  func resumeUpdate(
    throwing error: AccountServerSettingsTestError
  ) {
    updateContinuation?.resume(throwing: error)
    updateContinuation = nil
  }
}

private actor AccountServerAccountChangeRemoteStub:
  AccountServerRemoteServing {
  private let firstProfile: ServerAccountProfile
  private var secondProfileContinuation:
    CheckedContinuation<ServerAccountProfile, Error>?
  private var didRequestSecondProfile = false

  init(firstProfile: ServerAccountProfile) {
    self.firstProfile = firstProfile
  }

  func fetchProfile(
    memberID: Int64
  ) async throws -> ServerAccountProfile {
    guard memberID != firstProfile.memberID else {
      return firstProfile
    }

    didRequestSecondProfile = true
    return try await withCheckedThrowingContinuation {
      secondProfileContinuation = $0
    }
  }

  func fetchStreak(
    memberID: Int64
  ) async throws -> ServerAccountStreak {
    guard memberID == firstProfile.memberID else {
      throw AccountServerSettingsTestError.unavailable
    }
    return accountSettingsStreak()
  }

  func fetchVoices(
    memberID: Int64
  ) async throws -> [ServerTTSVoice] {
    guard memberID == firstProfile.memberID else {
      throw AccountServerSettingsTestError.unavailable
    }
    return [accountSettingsVoice(ttsID: 1)]
  }

  func updateTTS(
    ttsID: Int64,
    memberID: Int64
  ) async throws -> ServerTTSSelection {
    throw AccountServerSettingsTestError.unavailable
  }

  func waitUntilSecondProfileRequested() async {
    while !didRequestSecondProfile {
      await Task.yield()
    }
  }

  func resumeSecondProfile(
    throwing error: AccountServerSettingsTestError
  ) {
    secondProfileContinuation?.resume(throwing: error)
    secondProfileContinuation = nil
  }
}

nonisolated private func accountSettingsProfile(
  memberID: Int64 = 98
) -> ServerAccountProfile {
  ServerAccountProfile(
    memberID: memberID,
    nickname: "모루유저",
    loginType: .kakao,
    profileImageKey: nil,
    selectedTTSID: 1
  )
}

nonisolated private func accountSettingsStreak() -> ServerAccountStreak {
  ServerAccountStreak(
    currentDays: 5,
    bestDays: 12,
    weeklyStatus: [true, true, false, false, false, false, false]
  )
}

nonisolated private func accountSettingsVoice(
  ttsID: Int64,
  isProOnly: Bool = false
) -> ServerTTSVoice {
  ServerTTSVoice(
    ttsID: ttsID,
    voiceCode: "VOICE_\(ttsID)",
    displayName: "서버 음성 \(ttsID)",
    description: "서버 생성 음성",
    isProOnly: isProOnly
  )
}
