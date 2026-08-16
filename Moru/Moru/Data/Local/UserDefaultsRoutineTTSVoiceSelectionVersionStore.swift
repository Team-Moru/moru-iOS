//
//  UserDefaultsRoutineTTSVoiceSelectionVersionStore.swift
//  Moru
//

import Foundation

@MainActor
final class UserDefaultsRoutineTTSVoiceSelectionVersionStore:
  RoutineTTSVoiceSelectionVersionStoring {
  static let defaultKeyPrefix = "routine-tts-voice-selection-version-v1"

  private let userDefaults: UserDefaults
  private let keyPrefix: String

  init(
    userDefaults: UserDefaults = .standard,
    keyPrefix: String = UserDefaultsRoutineTTSVoiceSelectionVersionStore.defaultKeyPrefix
  ) {
    self.userDefaults = userDefaults
    self.keyPrefix = keyPrefix
  }

  func selectionVersion(forMemberID memberID: Int64) -> Int64? {
    guard let number = userDefaults.object(forKey: key(for: memberID)) as? NSNumber else {
      return nil
    }
    let version = number.int64Value
    guard version >= 0 else {
      removeSelectionVersion(forMemberID: memberID)
      return nil
    }
    return version
  }

  func setSelectionVersion(_ version: Int64, forMemberID memberID: Int64) {
    guard version >= 0 else {
      removeSelectionVersion(forMemberID: memberID)
      return
    }
    userDefaults.set(NSNumber(value: version), forKey: key(for: memberID))
  }

  func removeSelectionVersion(forMemberID memberID: Int64) {
    userDefaults.removeObject(forKey: key(for: memberID))
  }

  private func key(for memberID: Int64) -> String {
    "\(keyPrefix).\(memberID)"
  }
}
