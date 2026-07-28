//
//  VoiceCompatibilityTable.swift
//  Moru
//

import Foundation

/// Server voice codes map to bundled audio only through authoritative entries.
/// Display names and inferred personas are intentionally excluded.
nonisolated struct VoiceCompatibilityTable: Equatable, Sendable {
  /// No server-code-to-bundle contract is documented as of 2026-07-26.
  static let production = VoiceCompatibilityTable(entries: [:])

  private let localVoiceIDByServerCode: [String: String]

  init(entries: [String: String]) {
    self.localVoiceIDByServerCode = Dictionary(
      uniqueKeysWithValues: entries.map {
        (Self.normalizedServerVoiceCode($0.key), $0.value)
      }
    )
  }

  func localVoiceID(forServerVoiceCode voiceCode: String) -> String? {
    localVoiceIDByServerCode[Self.normalizedServerVoiceCode(voiceCode)]
  }

  func serverVoiceCode(forLocalVoiceID localVoiceID: String) -> String? {
    localVoiceIDByServerCode.first { $0.value == localVoiceID }?.key
  }

  static func normalizedServerVoiceCode(_ voiceCode: String) -> String {
    voiceCode
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
  }
}
