//
//  SessionStore.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Combine
import Foundation

@MainActor
final class SessionStore: ObservableObject {
  enum Phase: Equatable {
    case loading
    case onboardingRequired
    case alarmPermissionRequired
    case alarmRepairRequired
    case ready
    case failed(String)
  }

  @Published private(set) var snapshot: SessionSnapshot?
  @Published private(set) var profile: LocalProfile?
  @Published private(set) var phase: Phase = .loading

  func apply(snapshot: SessionSnapshot) {
    self.snapshot = snapshot
    profile = snapshot.profile.map(Self.makeProfile)
    phase = Self.phase(for: snapshot)
  }

  func apply(failure: AppLaunchFailure) {
    phase = .failed(failure.message)
  }

  static func isOnboardingComplete(snapshot: SessionSnapshot) -> Bool {
    guard snapshot.profile != nil, !hasNonterminalPlatformState(snapshot.platformStates) else {
      return false
    }

    return snapshot.activeRoutines.contains { routine in
      guard routine.isActive,
            let alarmSchedule = routine.alarmSchedule,
            alarmSchedule.isEnabled else {
        return false
      }

      return snapshot.platformStates.contains { state in
        state.scheduleID == alarmSchedule.id
          && state.routineID == routine.id
          && isConfigured(state)
      }
    }
  }

  private static func hasNonterminalPlatformState(_ states: [AlarmPlatformSnapshot]) -> Bool {
    states.contains { state in
      switch state.state {
      case .cancellationPending, .repairRequired:
        true
      case .configured, .cancelled:
        false
      }
    }
  }
  private static func isConfigured(_ state: AlarmPlatformSnapshot) -> Bool {
    switch state.state {
    case .configured:
      true
    case .cancellationPending, .cancelled, .repairRequired:
      false
    }
  }
  private static func makeProfile(_ snapshot: SessionProfileSnapshot) -> LocalProfile {
    LocalProfile(
      id: snapshot.id,
      displayName: snapshot.displayName,
      selectedVoice: VoiceProfile.preserving(id: snapshot.selectedVoiceID),
      createdAt: snapshot.createdAt,
      updatedAt: snapshot.updatedAt
    )
  }

  private static func phase(for snapshot: SessionSnapshot) -> Phase {
    if isOnboardingComplete(snapshot: snapshot) {
      return .ready
    }
    guard snapshot.profile != nil, hasEnabledRoutine(snapshot.activeRoutines) else {
      return .onboardingRequired
    }
    if snapshot.platformStates.contains(where: {
      $0.lastErrorCode == "notificationPermissionDenied"
    }) {
      return .alarmPermissionRequired
    }
    return .alarmRepairRequired
  }

  private static func hasEnabledRoutine(_ routines: [SessionRoutineSnapshot]) -> Bool {
    routines.contains { routine in
      routine.isActive && routine.alarmSchedule?.isEnabled == true
    }
  }
}
