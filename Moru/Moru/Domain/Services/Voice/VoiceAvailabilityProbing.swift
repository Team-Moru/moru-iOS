//
//  VoiceAvailabilityProbing.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import Foundation

protocol VoiceAvailabilityProbing {
  func isAvailable(_ voice: VoiceProfile) -> Bool
}

struct UnavailableVoiceAvailabilityProbe: VoiceAvailabilityProbing {
  func isAvailable(_ voice: VoiceProfile) -> Bool {
    false
  }
}
