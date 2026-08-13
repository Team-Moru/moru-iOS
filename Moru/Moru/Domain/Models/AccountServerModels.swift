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
}

nonisolated struct ServerTTSSelection: Equatable, Sendable {
  let memberID: Int64
  let ttsID: Int64
  let voiceCode: String
  let displayName: String
}
