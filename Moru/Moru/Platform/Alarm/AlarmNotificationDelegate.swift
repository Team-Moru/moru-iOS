//
//  AlarmNotificationDelegate.swift
//  Moru
//
//  Created by Codex on 7/23/26.
//

import Foundation
import UserNotifications

final class AlarmNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  init(center: UNUserNotificationCenter = .current()) {
    super.init()
    center.delegate = self
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    guard let envelope = Self.makeIngress(
      from: response.notification.request.content.userInfo,
      fireDate: response.notification.date,
      nonce: UUID()
    ) else {
      return
    }

    AlarmIngressOccurrenceStore.shared.savePendingEnvelope(envelope)
  }

  nonisolated static func makeIngress(
    from userInfo: [AnyHashable: Any],
    fireDate: Date,
    nonce: UUID
  ) -> AlarmIngressEnvelope? {
    UserNotificationAlarmSchedulingAdapter.ingress(from: userInfo)?
      .refreshingOccurrence(fireDate: fireDate, nonce: nonce)
      .routing(to: .alarmRing)
  }
}
