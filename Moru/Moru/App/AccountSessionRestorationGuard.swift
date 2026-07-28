//
//  AccountSessionRestorationGuard.swift
//  Moru
//

import Foundation

nonisolated protocol AccountSessionRestorationGuarding: Sendable {
  var isRestorationBlocked: Bool { get }

  func blockRestoration()
  func allowRestoration()
}

nonisolated final class InMemoryAccountSessionRestorationGuard:
  AccountSessionRestorationGuarding,
  @unchecked Sendable {
  private let lock = NSLock()
  private var isBlocked = false

  var isRestorationBlocked: Bool {
    lock.withLock { isBlocked }
  }

  func blockRestoration() {
    lock.withLock {
      isBlocked = true
    }
  }

  func allowRestoration() {
    lock.withLock {
      isBlocked = false
    }
  }
}

nonisolated final class UserDefaultsAccountSessionRestorationGuard:
  AccountSessionRestorationGuarding,
  @unchecked Sendable {
  static let defaultKey = "account-session-restoration-blocked-v1"

  private let userDefaults: UserDefaults
  private let key: String

  init(
    userDefaults: UserDefaults = .standard,
    key: String = UserDefaultsAccountSessionRestorationGuard.defaultKey
  ) {
    self.userDefaults = userDefaults
    self.key = key
  }

  var isRestorationBlocked: Bool {
    userDefaults.bool(forKey: key)
  }

  func blockRestoration() {
    userDefaults.set(true, forKey: key)
  }

  func allowRestoration() {
    userDefaults.removeObject(forKey: key)
  }
}
