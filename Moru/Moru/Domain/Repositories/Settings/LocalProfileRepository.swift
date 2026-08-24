//
//  LocalProfileRepository.swift
//  Moru
//

import Foundation

protocol LocalProfileRepository: AnyObject {
  @MainActor
  func fetchProfile() throws -> LocalProfile?
  @MainActor
  func loadOrCreateDefaultProfile() throws -> LocalProfile
  @MainActor
  func saveProfile(_ profile: LocalProfile) throws
  @MainActor
  func deleteProfile() throws
}

protocol LocalDataResetRepository: AnyObject {
  @MainActor
  func resetToFreshInstallState() throws
}
