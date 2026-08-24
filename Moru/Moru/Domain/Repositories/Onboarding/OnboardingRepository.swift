//
//  OnboardingRepository.swift
//  Moru
//

import Foundation

protocol OnboardingRepository: AnyObject {
  @MainActor
  func fetchProfile() throws -> LocalProfile?
  @MainActor
  func saveCompletion(profile: LocalProfile, routine: Routine) throws
}
