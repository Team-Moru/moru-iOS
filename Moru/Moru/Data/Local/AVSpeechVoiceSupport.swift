//
//  AVSpeechVoiceSupport.swift
//  Moru
//
//  Created by Codex on 7/18/26.
//

import AVFoundation

struct AVSpeechVoiceAvailabilityProbe: VoiceAvailabilityProbing {
  func isAvailable(_ voice: VoiceProfile) -> Bool {
    guard let identifier = Self.catalogueIdentifier(for: voice) else {
      return false
    }

    guard AVSpeechSynthesisVoice(identifier: identifier) != nil else {
      return false
    }

    return AVSpeechSynthesisVoice.speechVoices().contains { candidate in
      candidate.identifier == identifier
    }
  }

  static func catalogueIdentifier(for voice: VoiceProfile) -> String? {
    guard let identifier = catalogueIdentifiers[voice.id],
          voice.avSpeechVoiceIdentifier == identifier else {
      return nil
    }

    return identifier
  }

  private static let catalogueIdentifiers = [
    "moru.ko.yuna": "com.apple.ttsbundle.Yuna-compact",
    "moru.ko.sora": "com.apple.ttsbundle.Sora-compact"
  ]
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

  init(availabilityProbe: any VoiceAvailabilityProbing = AVSpeechVoiceAvailabilityProbe()) {
    self.availabilityProbe = availabilityProbe
  }

  @discardableResult
  func previewVoice(_ voice: VoiceProfile) -> Bool {
    guard availabilityProbe.isAvailable(voice),
          let identifier = AVSpeechVoiceAvailabilityProbe.catalogueIdentifier(for: voice),
          let speechVoice = AVSpeechSynthesisVoice(identifier: identifier) else {
      return false
    }

    let utterance = AVSpeechUtterance(string: "안녕하세요. 모루와 함께 아침 루틴을 시작해 볼까요?")
    utterance.voice = speechVoice

    synthesizer.stopSpeaking(at: .immediate)
    synthesizer.speak(utterance)
    return true
  }

  func stopVoicePreview() {
    synthesizer.stopSpeaking(at: .immediate)
  }
}
