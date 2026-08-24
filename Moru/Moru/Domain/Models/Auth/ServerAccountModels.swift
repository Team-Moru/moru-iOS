//
//  ServerAccountModels.swift
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
