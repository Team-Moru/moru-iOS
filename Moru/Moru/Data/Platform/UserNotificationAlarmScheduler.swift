//
//  UserNotificationAlarmScheduler.swift
//  Moru
//

import Foundation
import UserNotifications

@MainActor
protocol UserNotificationCenterScheduling: AnyObject {
  func authorizationStatus() async -> UNAuthorizationStatus
  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
  func removePendingNotificationRequests(withIdentifiers identifiers: [String])
  func removeDeliveredNotifications(withIdentifiers identifiers: [String])
  func add(_ request: UNNotificationRequest) async throws
}

@MainActor
private final class SystemUserNotificationCenter: UserNotificationCenterScheduling {
  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter) {
    self.center = center
  }

  func authorizationStatus() async -> UNAuthorizationStatus {
    await center.notificationSettings().authorizationStatus
  }

  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
    try await center.requestAuthorization(options: options)
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  func add(_ request: UNNotificationRequest) async throws {
    try await center.add(request)
  }
}

@MainActor
final class UserNotificationAlarmScheduler: AlarmNotificationScheduling {
  private let notificationCenter: any UserNotificationCenterScheduling

  init(center: UNUserNotificationCenter = .current()) {
    notificationCenter = SystemUserNotificationCenter(center: center)
  }

  init(notificationCenter: any UserNotificationCenterScheduling) {
    self.notificationCenter = notificationCenter
  }

  func authorizationState() async -> AlarmNotificationPermissionState {
    switch await notificationCenter.authorizationStatus() {
    case .notDetermined:
      return .notDetermined
    case .authorized, .provisional, .ephemeral:
      return .authorized
    case .denied:
      return .denied
    @unknown default:
      return .denied
    }
  }

  func requestAuthorization() async throws -> AlarmNotificationPermissionState {
    let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
    return granted ? .authorized : .denied
  }

  func replace(_ request: AlarmNotificationScheduleRequest) async throws {
    let identifiers = Self.requestIdentifiers(scheduleID: request.scheduleID)
    removeAllRequests(identifiers)

    do {
      for weekday in request.normalizedWeekdays {
        try await notificationCenter.add(makeNotificationRequest(request, weekday: weekday))
      }
    } catch {
      removeAllRequests(identifiers)
      throw error
    }
  }

  func cancel(scheduleID: UUID) async throws {
    removeAllRequests(Self.requestIdentifiers(scheduleID: scheduleID))
  }

  static func requestIdentifier(scheduleID: UUID, weekday: Weekday) -> String {
    "moru.notification.\(scheduleID.uuidString.lowercased()).weekday.\(weekday.rawValue)"
  }

  static func requestIdentifiers(scheduleID: UUID) -> [String] {
    Weekday.allCases
      .sorted { $0.rawValue < $1.rawValue }
      .map { requestIdentifier(scheduleID: scheduleID, weekday: $0) }
  }

  private func removeAllRequests(_ identifiers: [String]) {
    notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  private func makeNotificationRequest(
    _ request: AlarmNotificationScheduleRequest,
    weekday: Weekday
  ) -> UNNotificationRequest {
    var dateComponents = DateComponents()
    dateComponents.weekday = weekday.rawValue
    dateComponents.hour = request.hour
    dateComponents.minute = request.minute

    let content = UNMutableNotificationContent()
    content.title = "MORU"
    content.body = "\(request.routineName) 시작 시간이에요."
    content.sound = .default
    content.userInfo = [
      "schemaVersion": 1,
      "routineID": request.routineID.uuidString.lowercased(),
      "scheduleID": request.scheduleID.uuidString.lowercased()
    ]

    return UNNotificationRequest(
      identifier: Self.requestIdentifier(scheduleID: request.scheduleID, weekday: weekday),
      content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
    )
  }
}
