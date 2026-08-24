//
//  LocalProfile.swift
//  Moru
//

import Foundation

struct LocalProfile: Identifiable, Codable, Hashable {
  var id: UUID
  var displayName: String
  var selectedVoice: VoiceProfile
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    displayName: String = "모루 사용자",
    selectedVoice: VoiceProfile = .aoede,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.displayName = displayName
    self.selectedVoice = selectedVoice
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
