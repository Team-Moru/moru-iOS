//
//  ProfileServices.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import Foundation

enum ProfileAlarmStatus: Equatable {
  case configured
  case fallbackConfigured
  case permissionNotDetermined
  case permissionOff
  case repairRequired
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
  func currentStatus() async -> ProfileAlarmStatus
  func requestAuthorization() async -> ProfileAlarmStatus
  func retryScheduling() async -> ProfileAlarmStatus
  func cancelAllAlarms() async throws
}

@MainActor
final class UnavailableProfileAlarmService: ProfileAlarmServicing {
  func currentStatus() async -> ProfileAlarmStatus {
    .unavailable
  }

  func requestAuthorization() async -> ProfileAlarmStatus {
    .unavailable
  }

  func retryScheduling() async -> ProfileAlarmStatus {
    .unavailable
  }

  func cancelAllAlarms() async throws {}
}
