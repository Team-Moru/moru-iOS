//
//  OpenMoruRoutineIntent.swift
//  Moru
//
//  Created by 김승겸 on 7/12/26.
//

import AlarmKit
import AppIntents
import Foundation

nonisolated enum MoruAlarmRouteStore {
  static let didSaveNotification = Notification.Name(
    "moru.alarm.ingress.didSave"
  )

  private static let pendingEnvelopeKey = "moru.pendingAlarmIngressEnvelope"
  private static let lock = NSLock()

  static func savePendingEnvelope(
    _ envelope: AlarmIngressEnvelope,
    defaults: UserDefaults = .standard
  ) {
    persist(envelope, defaults: defaults)
    NotificationCenter.default.post(name: didSaveNotification, object: nil)
  }

  static func restorePendingEnvelope(
    _ envelope: AlarmIngressEnvelope,
    defaults: UserDefaults = .standard
  ) {
    persist(envelope, defaults: defaults)
  }

  private static func persist(
    _ envelope: AlarmIngressEnvelope,
    defaults: UserDefaults
  ) {
    lock.withLock {
      guard let data = try? JSONEncoder().encode(envelope) else {
        return
      }
      defaults.set(data, forKey: pendingEnvelopeKey)
    }
  }

  static func pendingEnvelope(
    defaults: UserDefaults = .standard
  ) -> AlarmIngressEnvelope? {
    lock.withLock {
      decodePendingEnvelope(defaults: defaults)
    }
  }

  static func consumePendingEnvelope(
    defaults: UserDefaults = .standard
  ) -> AlarmIngressEnvelope? {
    lock.withLock {
      let envelope = decodePendingEnvelope(defaults: defaults)
      defaults.removeObject(forKey: pendingEnvelopeKey)
      return envelope
    }
  }

  static func clear(defaults: UserDefaults = .standard) {
    lock.withLock {
      defaults.removeObject(forKey: pendingEnvelopeKey)
    }
  }

  private static func decodePendingEnvelope(
    defaults: UserDefaults
  ) -> AlarmIngressEnvelope? {
    guard let data = defaults.data(forKey: pendingEnvelopeKey) else {
      return nil
    }
    return try? JSONDecoder().decode(AlarmIngressEnvelope.self, from: data)
  }
}

public struct OpenMoruRoutineIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "MORU 루틴 시작"

  public static let description = IntentDescription(
    "MORU 앱을 열고 예약된 기상 루틴을 바로 시작합니다."
  )

  public static let openAppWhenRun = true

  @Parameter(title: "Alarm ingress")
  public var encodedIngress: String

  init(ingress: AlarmIngressEnvelope) {
    encodedIngress = (try? ingress.encodedString()) ?? ""
  }

  public init() {
    encodedIngress = ""
  }

  public func perform() async throws -> some IntentResult {
    guard let ingress = Self.makeIngress(
      encodedIngress: encodedIngress,
      fireDate: Date()
    ) else {
      return .result()
    }

    MoruAlarmRouteStore.savePendingEnvelope(ingress)
    return .result()
  }

  nonisolated static func makeIngress(
    encodedIngress: String,
    fireDate: Date,
    nonce: UUID = UUID()
  ) -> AlarmIngressEnvelope? {
    try? AlarmIngressEnvelope.decode(encodedIngress)
      .refreshingOccurrence(fireDate: fireDate, nonce: nonce)
      .routing(to: .scheduledRoutine)
  }
}
