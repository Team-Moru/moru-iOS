//
//  AccountServerModels.swift
//  Moru
//

import Foundation

nonisolated struct ServerAccountProfile: Equatable, Sendable {
  let memberID: Int64
  let nickname: String
  let loginType: ServerAccountLoginType
  let profileImageKey: String?
  let selectedTTSID: Int64
}

nonisolated enum ServerAccountLoginType: Equatable, Sendable {
  case google
  case naver
  case kakao
  case apple
  case unknown(String)
}

nonisolated struct ServerAccountStreak: Equatable, Sendable {
  let currentDays: Int
  let bestDays: Int

  /// Monday through Sunday, in server response order.
  let weeklyStatus: [Bool]
}

nonisolated struct ServerTTSVoice: Equatable, Sendable {
  let ttsID: Int64
  let voiceCode: String
  let displayName: String
  let description: String
  let isProOnly: Bool
  /// A pre-generated common sample. This stays optional while preview support
  /// is being rolled out on the backend.
  let previewAudioURL: URL?
  /// Voice-specific, pre-generated routine completion cue. This is separate
  /// from a routine INTRO generation and may be unavailable while the server
  /// is still preparing the asset.
  let doneAudio: ServerTTSCommonAudio
  /// Voice-specific, pre-generated no-speech reminder cue.
  let remindAudio: ServerTTSCommonAudio
  /// Version of the common cue files returned by `GET /tts`. Do not use this
  /// for the member's routine INTRO generation version.
  let commonAudioVersion: Int64?

  init(
    ttsID: Int64,
    voiceCode: String,
    displayName: String,
    description: String,
    isProOnly: Bool,
    previewAudioURL: URL? = nil,
    doneAudio: ServerTTSCommonAudio = .unavailable,
    remindAudio: ServerTTSCommonAudio = .unavailable,
    commonAudioVersion: Int64? = nil
  ) {
    self.ttsID = ttsID
    self.voiceCode = voiceCode
    self.displayName = displayName
    self.description = description
    self.isProOnly = isProOnly
    self.previewAudioURL = previewAudioURL
    self.doneAudio = doneAudio
    self.remindAudio = remindAudio
    self.commonAudioVersion = commonAudioVersion
  }
}

nonisolated struct ServerTTSCommonAudio: Equatable, Sendable {
  let status: ServerTTSCommonAudioStatus
  /// Set only when `status` is ready and the backend sent a valid HTTPS URL.
  let audioURL: URL?

  init(status: ServerTTSCommonAudioStatus, audioURL: URL?) {
    self.status = status
    self.audioURL = audioURL
  }

  static let unavailable = Self(status: .pending, audioURL: nil)

  var isPlayable: Bool {
    status == .ready && audioURL != nil
  }
}

nonisolated enum ServerTTSCommonAudioStatus: Equatable, Sendable {
  case ready
  case pending
  case unknown(String)

  init(serverValue: String?) {
    switch serverValue?.trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased() {
    case "READY":
      self = .ready
    case "PENDING", nil:
      self = .pending
    case let value?:
      self = .unknown(value)
    }
  }
}

nonisolated struct ServerTTSSelection: Equatable, Sendable {
  let memberID: Int64
  let ttsID: Int64
  let voiceCode: String
  let displayName: String
  /// Member selection/INTRO generation version from `PATCH /members/me/tts`.
  /// It is intentionally distinct from `ServerTTSVoice.commonAudioVersion`.
  let routineVoiceSelectionVersion: Int64?

  init(
    memberID: Int64,
    ttsID: Int64,
    voiceCode: String,
    displayName: String,
    selectionVersion: Int64? = nil
  ) {
    self.memberID = memberID
    self.ttsID = ttsID
    self.voiceCode = voiceCode
    self.displayName = displayName
    self.routineVoiceSelectionVersion = selectionVersion
  }

  /// Source-compatible spelling for callers that have not yet migrated.
  var selectionVersion: Int64? { routineVoiceSelectionVersion }
}
