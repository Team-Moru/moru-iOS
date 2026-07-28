//
//  MemoryAccessTokenProvider.swift
//  Moru
//

import Foundation

nonisolated final class MemoryAccessTokenProvider:
  AccessTokenProviding,
  @unchecked Sendable {
  private let lock = NSLock()
  private var snapshot: String?

  var accessToken: String? {
    lock.lock()
    defer { lock.unlock() }
    return snapshot
  }

  func replace(with accessToken: String?) {
    let normalized = accessToken?.trimmingCharacters(
      in: .whitespacesAndNewlines
    )

    lock.lock()
    snapshot = normalized?.isEmpty == false ? normalized : nil
    lock.unlock()
  }

  func remove() {
    replace(with: nil)
  }
}
