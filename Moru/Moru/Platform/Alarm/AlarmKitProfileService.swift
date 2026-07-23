//
//  AlarmKitProfileService.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import AlarmKit

@MainActor
final class AlarmKitProfileService: ProfileAlarmServicing {
  func currentStatus() -> ProfileAlarmStatus {
    switch AlarmManager.shared.authorizationState {
    case .authorized:
      .configured
    case .notDetermined:
      .permissionNotDetermined
    case .denied:
      .permissionOff
    @unknown default:
      .unavailable
    }
  }

  func requestAuthorization() async -> ProfileAlarmStatus {
    do {
      _ = try await AlarmManager.shared.requestAuthorization()
      return currentStatus()
    } catch {
      return .unavailable
    }
  }

  func cancelAllAlarms() throws {
    try AlarmManager.shared.alarms.forEach { alarm in
      try AlarmManager.shared.cancel(id: alarm.id)
    }
  }
}
