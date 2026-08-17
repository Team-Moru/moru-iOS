//
//  SessionStore.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Combine
import Foundation

nonisolated final class SessionStore: ObservableObject {
  enum Phase: Equatable {
    case loading
    case onboardingRequired
    case ready
    case failed(String)
  }

  let objectWillChange = ObservableObjectPublisher()

  private let localProfileRepository: any LocalProfileRepository

  private(set) var profile: LocalProfile? {
    willSet {
      objectWillChange.send()
    }
  }

  private(set) var phase: Phase = .loading {
    willSet {
      objectWillChange.send()
    }
  }

  @MainActor
  init(
    localProfileRepository: any LocalProfileRepository
  ) {
    self.localProfileRepository = localProfileRepository
  }

  @MainActor
  func load() {
    do {
      profile = try localProfileRepository.fetchProfile()
      phase = Self.phase(profile: profile)
    } catch {
      profile = nil
      phase = .failed(error.localizedDescription)
    }
  }

  @MainActor
  @discardableResult
  func createDefaultProfile() throws -> LocalProfile {
    do {
      let profile = try localProfileRepository.loadOrCreateDefaultProfile()
      self.profile = profile
      phase = Self.phase(profile: profile)
      return profile
    } catch {
      profile = nil
      phase = .failed(error.localizedDescription)
      throw error
    }
  }

  @MainActor
  func beginServerRoutineRestoration() {
    phase = .loading
  }

  @MainActor
  func finishServerRoutineRestoration() {
    load()
  }

  @MainActor
  func failServerRoutineRestoration() {
    phase = .failed(
      "서버 루틴을 불러오지 못했어요. 네트워크를 확인하고 다시 시도해 주세요."
    )
  }

  static func isSessionReady(profile: LocalProfile?) -> Bool {
    profile != nil
  }

  private static func phase(profile: LocalProfile?) -> Phase {
    isSessionReady(profile: profile)
      ? .ready
      : .onboardingRequired
  }
}
