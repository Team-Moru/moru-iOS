//
//  UserDefaultsOnboardingProgressStore.swift
//  Moru
//

import Foundation

@MainActor
final class UserDefaultsOnboardingProgressStore: OnboardingProgressStoring {
  static let defaultKey = "onboarding-account-entry-pending-v1"

  private let userDefaults: UserDefaults
  private let key: String

  init(
    userDefaults: UserDefaults = .standard,
    key: String = UserDefaultsOnboardingProgressStore.defaultKey
  ) {
    self.userDefaults = userDefaults
    self.key = key
  }

  var isAccountEntryPending: Bool {
    userDefaults.bool(forKey: key)
  }

  func setAccountEntryPending(_ isPending: Bool) {
    guard isPending else {
      userDefaults.removeObject(forKey: key)
      return
    }

    userDefaults.set(true, forKey: key)
  }
}
