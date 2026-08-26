//
//  VoiceProfile.swift
//  Moru
//

import Foundation

struct VoiceProfile: Codable, Hashable, Identifiable {
  var id: String
  var displayName: String
  var assetVoiceCode: String

  init(
    id: String,
    displayName: String,
    assetVoiceCode: String
  ) {
    self.id = id
    self.displayName = displayName
    self.assetVoiceCode = assetVoiceCode
  }

  static let aoede = VoiceProfile(
    id: "moru.bundle.aoede",
    displayName: "민서",
    assetVoiceCode: "Aoede"
  )

  static let charon = VoiceProfile(
    id: "moru.bundle.charon",
    displayName: "현우",
    assetVoiceCode: "Charon"
  )

  static let kore = VoiceProfile(
    id: "moru.bundle.kore",
    displayName: "지유",
    assetVoiceCode: "Kore"
  )

  static let orus = VoiceProfile(
    id: "moru.bundle.orus",
    displayName: "은우",
    assetVoiceCode: "Orus"
  )

  static let localVoices = [VoiceProfile.aoede, .charon, .kore, .orus]

  static func fallback(id: String) -> VoiceProfile {
    localVoices.first { $0.id == id } ?? .aoede
  }
}
