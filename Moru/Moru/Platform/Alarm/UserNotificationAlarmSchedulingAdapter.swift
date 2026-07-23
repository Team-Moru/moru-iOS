//
//  UserNotificationAlarmSchedulingAdapter.swift
//  Moru
//
//  Created by Codex on 7/23/26.
//

import Foundation
import UserNotifications

@MainActor
final class UserNotificationAlarmSchedulingAdapter: AlarmScheduling {
  static let identifierPrefix = "moru.alarm."

  let backend = AlarmDeliveryBackend.localNotification
  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func authorizationState() async -> AlarmAuthorizationState {
    let settings = await center.notificationSettings()
    return Self.makeAuthorizationState(from: settings.authorizationStatus)
  }

  func requestAuthorization() async throws -> AlarmAuthorizationState {
    _ = try await center.requestAuthorization(options: [.alert, .sound])
    return await authorizationState()
  }

  func scheduleRecurring(_ request: AlarmScheduleRequest) async throws -> [String] {
    var scheduledIdentifiers: [String] = []
    let ingress = AlarmIngressEnvelope(
      alarmID: request.scheduleID,
      routineID: request.routineID,
      scheduleID: request.scheduleID,
      kind: .recurring,
      fireDate: Date(),
      nonce: UUID()
    )

    do {
      for weekday in request.weekdays {
        let identifier = Self.requestIdentifier(
          scheduleID: request.scheduleID,
          weekday: weekday
        )
        let notificationRequest = UNNotificationRequest(
          identifier: identifier,
          content: makeContent(
            routineName: request.routineName,
            ingress: ingress
          ),
          trigger: UNCalendarNotificationTrigger(
            dateMatching: DateComponents(
              hour: request.hour,
              minute: request.minute,
              weekday: weekday.rawValue
            ),
            repeats: true
          )
        )
        try await center.add(notificationRequest)
        scheduledIdentifiers.append(identifier)
      }
      return scheduledIdentifiers
    } catch {
      center.removePendingNotificationRequests(
        withIdentifiers: scheduledIdentifiers
      )
      throw error
    }
  }

  func scheduleSnooze(_ request: AlarmSnoozeRequest) async throws -> [String] {
    let identifier = Self.snoozeRequestIdentifier(alarmID: request.alarmID)
    var dateComponents = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: request.fireDate
    )
    dateComponents.timeZone = .current
    let notificationRequest = UNNotificationRequest(
      identifier: identifier,
      content: makeContent(
        routineName: request.routineName,
        ingress: request.ingressEnvelope
      ),
      trigger: UNCalendarNotificationTrigger(
        dateMatching: dateComponents,
        repeats: false
      )
    )
    try await center.add(notificationRequest)
    return [identifier]
  }

  func stop(id: UUID) async throws {
    let alarmID = id.uuidString.lowercased()
    let identifiers = await center.deliveredNotifications()
      .filter { notification in
        guard let ingress = Self.ingress(
          from: notification.request.content.userInfo
        ) else {
          return false
        }
        return ingress.alarmID.uuidString.lowercased() == alarmID
      }
      .map { $0.request.identifier }
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  func cancel(identifiers: [String]) async throws {
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  func snapshot() async throws -> AlarmPlatformSnapshot {
    let identifiers = await center.pendingNotificationRequests()
      .map(\.identifier)
      .filter { $0.hasPrefix(Self.identifierPrefix) }
    return AlarmPlatformSnapshot(
      backend: backend,
      identifiers: Set(identifiers)
    )
  }

  static func requestIdentifier(
    scheduleID: UUID,
    weekday: Weekday
  ) -> String {
    "\(identifierPrefix)\(scheduleID.uuidString.lowercased()).weekday.\(weekday.rawValue)"
  }

  static func snoozeRequestIdentifier(alarmID: UUID) -> String {
    "\(identifierPrefix)\(alarmID.uuidString.lowercased()).snooze"
  }

  nonisolated static func ingress(
    from userInfo: [AnyHashable: Any]
  ) -> AlarmIngressEnvelope? {
    guard let value = userInfo[AlarmIngressEnvelope.notificationUserInfoKey]
      as? String else {
      return nil
    }
    return try? AlarmIngressEnvelope.decode(value)
  }

  private func makeContent(
    routineName: String,
    ingress: AlarmIngressEnvelope
  ) -> UNNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = "\(routineName) 시작할 시간이에요"
    content.body = "MORU를 열어 루틴을 시작해 주세요."
    content.sound = .default
    content.userInfo = [
      AlarmIngressEnvelope.notificationUserInfoKey:
        (try? ingress.encodedString()) ?? "",
    ]
    return content
  }

  private static func makeAuthorizationState(
    from status: UNAuthorizationStatus
  ) -> AlarmAuthorizationState {
    switch status {
    case .notDetermined:
      .notDetermined
    case .denied:
      .denied
    case .authorized, .provisional, .ephemeral:
      .authorized
    @unknown default:
      .unavailable
    }
  }
}
