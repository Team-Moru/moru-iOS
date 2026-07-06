//
//  SessionStore.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
  enum Phase: Equatable {
    case loading
    case onboardingRequired
    case ready
    case failed(String)
  }

  private let localProfileRepository: any LocalProfileRepository

  private(set) var profile: LocalProfile?
  private(set) var phase: Phase = .loading

  init(localProfileRepository: any LocalProfileRepository) {
    self.localProfileRepository = localProfileRepository
  }

  func load() {
    do {
      profile = try localProfileRepository.fetchProfile()
      phase = profile == nil ? .onboardingRequired : .ready
    } catch {
      profile = nil
      phase = .failed(error.localizedDescription)
    }
  }

  @discardableResult
  func createDefaultProfile() throws -> LocalProfile {
    let profile = try localProfileRepository.loadOrCreateDefaultProfile()
    self.profile = profile
    phase = .ready
    return profile
  }
}
