//
//  SessionStore.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
  enum Phase: Equatable {
    case loading
    case onboardingRequired
    case ready
    case failed(String)
  }

  private let localProfileRepository: any LocalProfileRepository
  private let routineRepository: any RoutineRepository

  @Published private(set) var profile: LocalProfile?
  @Published private(set) var phase: Phase = .loading

  init(
    localProfileRepository: any LocalProfileRepository,
    routineRepository: any RoutineRepository
  ) {
    self.localProfileRepository = localProfileRepository
    self.routineRepository = routineRepository
  }

  func load() {
    do {
      profile = try localProfileRepository.fetchProfile()
      let activeRoutines = try routineRepository.fetchActiveRoutines()
      phase = Self.phase(profile: profile, activeRoutines: activeRoutines)
    } catch {
      profile = nil
      phase = .failed(error.localizedDescription)
    }
  }

  @discardableResult
  func createDefaultProfile() throws -> LocalProfile {
    let profile = try localProfileRepository.loadOrCreateDefaultProfile()
    let activeRoutines = try routineRepository.fetchActiveRoutines()
    self.profile = profile
    phase = Self.phase(profile: profile, activeRoutines: activeRoutines)
    return profile
  }

  static func isOnboardingComplete(
    profile: LocalProfile?,
    activeRoutines: [Routine]
  ) -> Bool {
    guard profile != nil else {
      return false
    }

    return activeRoutines.contains { routine in
      routine.isActive && routine.alarmSchedule?.isEnabled == true
    }
  }

  private static func phase(
    profile: LocalProfile?,
    activeRoutines: [Routine]
  ) -> Phase {
    isOnboardingComplete(profile: profile, activeRoutines: activeRoutines)
      ? .ready
      : .onboardingRequired
  }
}
