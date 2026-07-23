//
//  BundledVoiceSupport.swift
//  Moru
//

import Foundation

struct BundledVoiceAvailabilityProbe: VoiceAvailabilityProbing {
  static let previewItemID = "ENERGY-02"

  private let resourceLoader: RoutineAudioResourceLoader

  init(resourceLoader: RoutineAudioResourceLoader) {
    self.resourceLoader = resourceLoader
  }

  func isAvailable(_ voice: VoiceProfile) -> Bool {
    guard VoiceProfile.localVoices.contains(voice) else {
      return false
    }

    do {
      guard let cue = try resourceLoader.cue(
        itemID: Self.previewItemID,
        voiceCode: voice.assetVoiceCode,
        kind: .intro
      ) else {
        return false
      }

      return resourceLoader.resourceURL(for: cue) != nil
    } catch {
      return false
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
final class BundledVoicePreviewPlayer: VoicePreviewPlaying {
  private let availabilityProbe: any VoiceAvailabilityProbing
  private let guidancePlayer: any RoutineGuidancePlaying
  private var previewGeneration = 0

  init(
    availabilityProbe: any VoiceAvailabilityProbing,
    guidancePlayer: any RoutineGuidancePlaying
  ) {
    self.availabilityProbe = availabilityProbe
    self.guidancePlayer = guidancePlayer
  }

  @discardableResult
  func previewVoice(_ voice: VoiceProfile) -> Bool {
    guard availabilityProbe.isAvailable(voice) else {
      return false
    }

    previewGeneration += 1
    let generation = previewGeneration

    Task { [weak self] in
      guard let self, generation == previewGeneration else {
        return
      }

      _ = await guidancePlayer.play(
        itemID: BundledVoiceAvailabilityProbe.previewItemID,
        voiceCode: voice.assetVoiceCode,
        kind: .intro
      )
    }
    return true
  }

  func stopVoicePreview() {
    previewGeneration += 1
    guidancePlayer.stop()
  }
}

@MainActor
final class UnavailableVoicePreviewPlayer: VoicePreviewPlaying {
  func previewVoice(_ voice: VoiceProfile) -> Bool {
    false
  }

  func stopVoicePreview() {}
}
