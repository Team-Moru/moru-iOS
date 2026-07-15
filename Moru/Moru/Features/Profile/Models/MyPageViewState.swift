//
//  MyPageViewState.swift
//  Moru
//
//  Created by Codex on 7/13/26.
//

import Foundation

struct MyPageViewState: Equatable {
  var displayName: String
  var selectedVoice: VoiceProfile
  var availableVoices: [VoiceProfile]
  var isLoading: Bool
  var errorMessage: String?

  static let placeholder = MyPageViewState(
    displayName: "모루 사용자",
    selectedVoice: .moru,
    availableVoices: VoiceProfile.localVoices,
    isLoading: false,
    errorMessage: nil
  )
}
