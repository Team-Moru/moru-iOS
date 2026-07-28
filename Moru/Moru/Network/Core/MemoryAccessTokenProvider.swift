//
//  MemoryAccessTokenProvider.swift
//  Moru
//

import Foundation

nonisolated final class MemoryAccessTokenProvider:
  AccountBoundAccessTokenProviding,
  @unchecked Sendable {
  private let lock = NSLock()
  private var snapshot: String?
  private var memberID: Int64?
  private var sessionID: UUID?

  var accessToken: String? {
    lock.lock()
    defer { lock.unlock() }
    return snapshot
  }

  func replace(with accessToken: String?) {
    let normalized = Self.normalized(accessToken)

    lock.lock()
    snapshot = normalized
    memberID = nil
    sessionID = nil
    lock.unlock()
  }

  func establishAccountSession(
    with accessToken: String?,
    memberID: Int64
  ) {
    let normalized = memberID > 0
      ? Self.normalized(accessToken)
      : nil

    lock.lock()
    snapshot = normalized
    self.memberID = normalized == nil ? nil : memberID
    sessionID = normalized == nil ? nil : UUID()
    lock.unlock()
  }

  @discardableResult
  func replaceAccountSessionToken(
    with accessToken: String?,
    memberID: Int64
  ) -> Bool {
    let normalized = Self.normalized(accessToken)

    lock.lock()
    defer { lock.unlock() }

    guard memberID > 0,
          self.memberID == memberID,
          sessionID != nil,
          normalized != nil else {
      return false
    }

    snapshot = normalized
    return true
  }

  func authorizationContext(
    forMemberID memberID: Int64
  ) -> AccountAuthorizationContext? {
    lock.lock()
    defer { lock.unlock() }

    guard memberID > 0,
          self.memberID == memberID,
          let snapshot,
          let sessionID else {
      return nil
    }

    return AccountAuthorizationContext(
      memberID: memberID,
      accessToken: snapshot,
      sessionID: sessionID
    )
  }

  func remove() {
    replace(with: nil)
  }

  private static func normalized(_ accessToken: String?) -> String? {
    let normalized = accessToken?.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    return normalized?.isEmpty == false ? normalized : nil
  }
}
