//
//  UserDefaultsRoutineTTSVoiceSelectionVersionStore.swift
//  Moru
//

import Foundation

@MainActor
final class UserDefaultsRoutineTTSVoiceSelectionVersionStore:
  RoutineTTSVoiceSelectionVersionStoring {
  static let defaultKeyPrefix = "routine-tts-voice-selection-version-v1"
  static let defaultTTSIDKeyPrefix = "routine-tts-selected-tts-id-v1"

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

  func selectedTTSID(forMemberID memberID: Int64) -> Int64? {
    guard let number = userDefaults.object(
      forKey: ttsIDKey(for: memberID)
    ) as? NSNumber else {
      return nil
    }
    let ttsID = number.int64Value
    guard ttsID > 0 else {
      removeSelectedTTSID(forMemberID: memberID)
      return nil
    }
    return ttsID
  }

  func setSelectedTTSID(_ ttsID: Int64, forMemberID memberID: Int64) {
    guard ttsID > 0 else {
      removeSelectedTTSID(forMemberID: memberID)
      return
    }
    userDefaults.set(NSNumber(value: ttsID), forKey: ttsIDKey(for: memberID))
  }

  func removeSelectedTTSID(forMemberID memberID: Int64) {
    userDefaults.removeObject(forKey: ttsIDKey(for: memberID))
  }

  private func key(for memberID: Int64) -> String {
    "\(keyPrefix).\(memberID)"
  }

  private func ttsIDKey(for memberID: Int64) -> String {
    "\(Self.defaultTTSIDKeyPrefix).\(memberID)"
  }
}
