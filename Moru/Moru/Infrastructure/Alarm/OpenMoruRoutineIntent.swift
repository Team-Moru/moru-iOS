//
//  OpenMoruRoutineIntent.swift
//  Moru
//
//  Created by 김승겸 on 7/12/26.
//

import AlarmKit
import AppIntents
import Foundation

nonisolated final class AlarmIngressOccurrenceStore: @unchecked Sendable {
  static let shared = AlarmIngressOccurrenceStore()

  static let didSaveNotification = Notification.Name(
    "moru.alarm.ingress.didSave"
  )

  private struct StoredState: Codable {
    var pendingEnvelope: AlarmIngressEnvelope?
    var claimedEnvelope: AlarmIngressEnvelope?
    var consumedEnvelopes: [AlarmIngressEnvelope]

    static let empty = StoredState(
      pendingEnvelope: nil,
      claimedEnvelope: nil,
      consumedEnvelopes: []
    )
  }

  private static let stateKey = "moru.pendingAlarmIngressEnvelope"
  private static let maximumConsumedOccurrenceCount = 64
  private static let duplicateOccurrenceTolerance: TimeInterval = 30 * 60

  private let defaults: UserDefaults
  private let notificationCenter: NotificationCenter
  private let lock = NSLock()
  private var claimedNonces: Set<UUID> = []

  init(
    defaults: UserDefaults = .standard,
    notificationCenter: NotificationCenter = .default
  ) {
    self.defaults = defaults
    self.notificationCenter = notificationCenter
  }

  @discardableResult
  func savePendingEnvelope(_ envelope: AlarmIngressEnvelope) -> Bool {
    let didSave = lock.withLock {
      var state = loadState()
      guard !state.consumedEnvelopes.contains(where: {
        Self.isSameOccurrence($0, envelope)
      }) else {
        return false
      }
      guard state.claimedEnvelope == nil else {
        return false
      }
      if let pendingEnvelope = state.pendingEnvelope,
         Self.isSameOccurrence(pendingEnvelope, envelope) {
        return false
      }

      state.pendingEnvelope = envelope
      return persist(state)
    }

    if didSave {
      notificationCenter.post(name: Self.didSaveNotification, object: nil)
    }
    return didSave
  }

  func pendingEnvelope() -> AlarmIngressEnvelope? {
    lock.withLock {
      let state = loadState()
      return state.claimedEnvelope ?? state.pendingEnvelope
    }
  }

  func claimPendingEnvelope() -> AlarmIngressEnvelope? {
    lock.withLock {
      var state = loadState()

      if let claimedEnvelope = state.claimedEnvelope {
        guard claimedNonces.insert(claimedEnvelope.nonce).inserted else {
          return nil
        }
        return claimedEnvelope
      }

      guard let pendingEnvelope = state.pendingEnvelope else {
        return nil
      }
      state.pendingEnvelope = nil
      state.claimedEnvelope = pendingEnvelope
      guard persist(state) else {
        return nil
      }
      claimedNonces.insert(pendingEnvelope.nonce)
      return pendingEnvelope
    }
  }

  func complete(_ envelope: AlarmIngressEnvelope) {
    lock.withLock {
      var state = loadState()
      guard let claimedEnvelope = state.claimedEnvelope,
            Self.isSameOccurrence(claimedEnvelope, envelope) else {
        return
      }

      state.claimedEnvelope = nil
      if let pendingEnvelope = state.pendingEnvelope,
         Self.isSameOccurrence(pendingEnvelope, envelope) {
        state.pendingEnvelope = nil
      }
      state.consumedEnvelopes.removeAll {
        Self.isSameOccurrence($0, envelope)
      }
      state.consumedEnvelopes.append(envelope)
      if state.consumedEnvelopes.count > Self.maximumConsumedOccurrenceCount {
        state.consumedEnvelopes.removeFirst(
          state.consumedEnvelopes.count - Self.maximumConsumedOccurrenceCount
        )
      }
      claimedNonces.remove(claimedEnvelope.nonce)
      _ = persist(state)
    }
  }

  func release(_ envelope: AlarmIngressEnvelope) {
    lock.withLock {
      var state = loadState()
      guard let claimedEnvelope = state.claimedEnvelope,
            Self.isSameOccurrence(claimedEnvelope, envelope) else {
        return
      }

      state.claimedEnvelope = nil
      state.pendingEnvelope = envelope
      claimedNonces.remove(claimedEnvelope.nonce)
      _ = persist(state)
    }
  }

  func clear() {
    lock.withLock {
      claimedNonces.removeAll()
      defaults.removeObject(forKey: Self.stateKey)
    }
  }

  private func loadState() -> StoredState {
    guard let data = defaults.data(forKey: Self.stateKey) else {
      return .empty
    }
    if let state = try? JSONDecoder().decode(StoredState.self, from: data) {
      return state
    }
    if let legacyEnvelope = try? JSONDecoder().decode(
      AlarmIngressEnvelope.self,
      from: data
    ) {
      return StoredState(
        pendingEnvelope: legacyEnvelope,
        claimedEnvelope: nil,
        consumedEnvelopes: []
      )
    }

    defaults.removeObject(forKey: Self.stateKey)
    return .empty
  }

  private func persist(_ state: StoredState) -> Bool {
    guard let data = try? JSONEncoder().encode(state) else {
      return false
    }
    defaults.set(data, forKey: Self.stateKey)
    return true
  }

  private static func isSameOccurrence(
    _ lhs: AlarmIngressEnvelope,
    _ rhs: AlarmIngressEnvelope
  ) -> Bool {
    if lhs.nonce == rhs.nonce {
      return true
    }
    guard lhs.alarmID == rhs.alarmID,
          lhs.routineID == rhs.routineID,
          lhs.scheduleID == rhs.scheduleID,
          lhs.kind == rhs.kind else {
      return false
    }
    return abs(lhs.fireDate.timeIntervalSince(rhs.fireDate))
      <= duplicateOccurrenceTolerance
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

    AlarmIngressOccurrenceStore.shared.savePendingEnvelope(ingress)
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
