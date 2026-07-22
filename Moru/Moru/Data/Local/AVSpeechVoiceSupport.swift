//
//  AVSpeechVoiceSupport.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import AVFoundation

struct AVSpeechVoiceAvailabilityProbe: VoiceAvailabilityProbing {
  func isAvailable(_ voice: VoiceProfile) -> Bool {
    guard let identifier = voice.avSpeechVoiceIdentifier,
          AVSpeechSynthesisVoice(identifier: identifier) != nil else {
      return false
    }

    return AVSpeechSynthesisVoice.speechVoices().contains { candidate in
      candidate.identifier == identifier
    }
  }
}

@MainActor
protocol VoicePreviewPlaying: AnyObject {
  @discardableResult
  func previewVoice(_ voice: VoiceProfile) -> Bool
  func stopVoicePreview()
}

@MainActor
final class AVSpeechVoicePreviewPlayer: VoicePreviewPlaying {
  private let availabilityProbe: any VoiceAvailabilityProbing
  private let synthesizer = AVSpeechSynthesizer()

  init(availabilityProbe: any VoiceAvailabilityProbing) {
    self.availabilityProbe = availabilityProbe
  }

  @discardableResult
  func previewVoice(_ voice: VoiceProfile) -> Bool {
    guard availabilityProbe.isAvailable(voice),
          let identifier = voice.avSpeechVoiceIdentifier,
          let speechVoice = AVSpeechSynthesisVoice(identifier: identifier) else {
      return false
    }

    let utterance = AVSpeechUtterance(
      string: "안녕하세요. 모루와 함께 아침 루틴을 시작해 볼까요?"
    )
    utterance.voice = speechVoice
    synthesizer.stopSpeaking(at: .immediate)
    synthesizer.speak(utterance)
    return true
  }

  func stopVoicePreview() {
    synthesizer.stopSpeaking(at: .immediate)
  }
}
