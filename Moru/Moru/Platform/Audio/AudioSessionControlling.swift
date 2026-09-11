//
//  AudioSessionControlling.swift
//  Moru
//

import AVFoundation

/// `AVAudioSession` 호출을 가로챌 수 있게 만든 얇은 경계.
///
/// 지금은 네 타입이 중재 없이 전역 세션을 만진다. 소유자를 하나로 모으기 전에
/// 누가 언제 무엇을 호출하는지 테스트로 먼저 고정하려고 넣었다.
@MainActor
protocol AudioSessionControlling: AnyObject {
  func setCategory(
    _ category: AVAudioSession.Category,
    mode: AVAudioSession.Mode,
    options: AVAudioSession.CategoryOptions
  ) throws

  func setActive(
    _ active: Bool,
    options: AVAudioSession.SetActiveOptions
  ) throws
}

extension AudioSessionControlling {
  func setActive(_ active: Bool) throws {
    try setActive(active, options: [])
  }
}

extension AVAudioSession: AudioSessionControlling {}
