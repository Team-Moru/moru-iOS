//
//  ProfileServices.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import Foundation

enum ProfileAlarmStatus: Equatable {
  case configured
  case permissionNotDetermined
  case permissionOff
  case unavailable
}

protocol VoiceAvailabilityProbing {
  func isAvailable(_ voice: VoiceProfile) -> Bool
}

struct UnavailableVoiceAvailabilityProbe: VoiceAvailabilityProbing {
  func isAvailable(_ voice: VoiceProfile) -> Bool {
    false
  }
}

@MainActor
protocol ProfileAlarmServicing: AnyObject {
  func currentStatus() -> ProfileAlarmStatus
  func requestAuthorization() async -> ProfileAlarmStatus
  func cancelAllAlarms() throws
}

@MainActor
final class UnavailableProfileAlarmService: ProfileAlarmServicing {
  func currentStatus() -> ProfileAlarmStatus {
    .unavailable
  }

  func requestAuthorization() async -> ProfileAlarmStatus {
    .unavailable
  }

  func cancelAllAlarms() throws {}
}
