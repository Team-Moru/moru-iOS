//
//  AccountServerSettingsViewModel.swift
//  Moru
//

import Foundation
import Observation

@MainActor
enum AccountServerResourceState<Value: Equatable>: Equatable {
  case unavailable
  case signedOut
  case loading(previous: Value?)
  case content(Value)
  case empty
  case failed(previous: Value?)

  var value: Value? {
    switch self {
    case .loading(let previous), .failed(let previous):
      previous
    case .content(let value):
      value
    case .unavailable, .signedOut, .empty:
      nil
    }
  }
}

@MainActor
@Observable
final class AccountServerSettingsViewModel {
  private let remoteService: (any AccountServerRemoteServing)?
  private var loadGeneration = 0
  private var currentMemberID: Int64?

  private(set) var profileState:
    AccountServerResourceState<ServerAccountProfile> = .signedOut
  private(set) var streakState:
    AccountServerResourceState<ServerAccountStreak> = .signedOut
  private(set) var voiceState:
    AccountServerResourceState<[ServerTTSVoice]> = .signedOut
  private(set) var subscriptionState:
    AccountServerResourceState<ServerSubscriptionInfo> = .signedOut
  private(set) var selectedTTSID: Int64?
  private(set) var latestSelection: ServerTTSSelection?
  private(set) var isUpdatingVoice = false
  private(set) var updatingTTSID: Int64?
  private(set) var voiceUpdateErrorMessage: String?

  init(remoteService: (any AccountServerRemoteServing)? = nil) {
    self.remoteService = remoteService
  }

  func load(memberID: Int64?) async {
    let previousMemberID = currentMemberID
    loadGeneration += 1
    let generation = loadGeneration
    currentMemberID = memberID
    isUpdatingVoice = false
    updatingTTSID = nil
    voiceUpdateErrorMessage = nil
    latestSelection = nil

    guard let memberID, memberID > 0 else {
      applySignedOutState()
      return
    }
    guard let remoteService else {
      applyUnavailableState()
      return
    }

    let preservesPreviousValues = previousMemberID == memberID
    let previousProfile = preservesPreviousValues
      ? profileState.value
      : nil
    let previousStreak = preservesPreviousValues
      ? streakState.value
      : nil
    let previousVoices = preservesPreviousValues
      ? voiceState.value
      : nil
    let previousSubscription = preservesPreviousValues
      ? subscriptionState.value
      : nil
    if !preservesPreviousValues {
      selectedTTSID = nil
    }
    profileState = .loading(previous: previousProfile)
    streakState = .loading(previous: previousStreak)
    voiceState = .loading(previous: previousVoices)
    subscriptionState = .loading(previous: previousSubscription)

    async let profileOutcome = accountServerLoadOutcome {
      try await remoteService.fetchProfile(memberID: memberID)
    }
    async let streakOutcome = accountServerLoadOutcome {
      try await remoteService.fetchStreak(memberID: memberID)
    }
    async let voiceOutcome = accountServerLoadOutcome {
      try await remoteService.fetchVoices(memberID: memberID)
    }
    async let subscriptionOutcome = accountServerLoadOutcome {
      try await remoteService.fetchSubscription(memberID: memberID)
    }
    let outcomes = await (
      profileOutcome,
      streakOutcome,
      voiceOutcome,
      subscriptionOutcome
    )

    guard !Task.isCancelled,
          generation == loadGeneration,
          currentMemberID == memberID else {
      return
    }

    profileState = resourceState(
      from: outcomes.0,
      previous: previousProfile
    )
    streakState = resourceState(
      from: outcomes.1,
      previous: previousStreak
    )
    voiceState = resourceState(
      from: outcomes.2,
      previous: previousVoices,
      treatsEmptyCollectionAsEmpty: true
    )
    subscriptionState = resourceState(
      from: outcomes.3,
      previous: previousSubscription
    )

    if case .content(let profile) = profileState {
      selectedTTSID = profile.selectedTTSID
    } else if previousProfile == nil {
      selectedTTSID = nil
    }
  }

  func selectVoice(
    _ voice: ServerTTSVoice,
    memberID: Int64?
  ) async {
    guard !isUpdatingVoice,
          let memberID,
          memberID > 0,
          memberID == currentMemberID,
          let remoteService,
          voiceState.value?.contains(voice) == true else {
      return
    }
    guard !voice.isProOnly || hasActiveProSubscription else {
      voiceUpdateErrorMessage =
        "PRO 구독을 확인한 뒤 이 서버 음성을 선택할 수 있어요."
      return
    }

    let generation = loadGeneration
    isUpdatingVoice = true
    updatingTTSID = voice.ttsID
    voiceUpdateErrorMessage = nil
    defer {
      if generation == loadGeneration,
        currentMemberID == memberID {
        isUpdatingVoice = false
        updatingTTSID = nil
      }
    }

    do {
      let selection = try await remoteService.updateTTS(
        ttsID: voice.ttsID,
        memberID: memberID
      )
      try Task.checkCancellation()
      guard generation == loadGeneration,
            currentMemberID == memberID else {
        return
      }

      latestSelection = selection
      selectedTTSID = selection.ttsID
    } catch is CancellationError {
      return
    } catch {
      guard generation == loadGeneration,
            currentMemberID == memberID else {
        return
      }
      voiceUpdateErrorMessage =
        "서버 음성을 변경하지 못했어요. 기존 선택은 유지됩니다."
    }
  }

  var hasActiveProSubscription: Bool {
    guard case .content(let subscription) = subscriptionState,
          subscription.plan == .pro else {
      return false
    }
    return subscription.isActive
  }

  var selectedVoiceDisplayName: String {
    if let latestSelection,
       latestSelection.ttsID == selectedTTSID {
      return latestSelection.displayName
    }
    if let selectedTTSID,
       let voice = voiceState.value?.first(
        where: { $0.ttsID == selectedTTSID }
       ) {
      return voice.displayName
    }
    return "선택 정보 확인 중"
  }

  private func applySignedOutState() {
    profileState = .signedOut
    streakState = .signedOut
    voiceState = .signedOut
    subscriptionState = .signedOut
    selectedTTSID = nil
  }

  private func applyUnavailableState() {
    profileState = .unavailable
    streakState = .unavailable
    voiceState = .unavailable
    subscriptionState = .unavailable
    selectedTTSID = nil
  }

  private func resourceState<Value: Equatable & Sendable>(
    from outcome: AccountServerLoadOutcome<Value>,
    previous: Value?,
    treatsEmptyCollectionAsEmpty: Bool = false
  ) -> AccountServerResourceState<Value> {
    switch outcome {
    case .success(let value):
      if treatsEmptyCollectionAsEmpty,
         let collection = value as? any Collection,
         collection.isEmpty {
        return .empty
      }
      return .content(value)
    case .failed:
      return .failed(previous: previous)
    case .cancelled:
      return .loading(previous: previous)
    }
  }
}

nonisolated private enum AccountServerLoadOutcome<Value: Sendable>: Sendable {
  case success(Value)
  case failed
  case cancelled
}

nonisolated private func accountServerLoadOutcome<Value: Sendable>(
  _ operation: @escaping @Sendable () async throws -> Value
) async -> AccountServerLoadOutcome<Value> {
  do {
    return .success(try await operation())
  } catch is CancellationError {
    return .cancelled
  } catch {
    return .failed
  }
}
