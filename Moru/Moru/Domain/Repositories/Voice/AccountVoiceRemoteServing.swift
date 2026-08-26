//
//  AccountVoiceRemoteServing.swift
//  Moru
//

import Foundation

/// 로그인한 회원의 음성 카탈로그 조회와 선택 음성 변경.
///
/// 회원이 현재 선택한 음성 ID는 이 계약이 아니라
/// `AccountProfileRemoteServing.fetchProfile`의 `selectedTTSID`로 읽는다.
nonisolated protocol AccountVoiceRemoteServing: Sendable {
  func fetchVoices(memberID: Int64) async throws -> [ServerTTSVoice]
  func updateTTS(
    ttsID: Int64,
    memberID: Int64
  ) async throws -> ServerTTSSelection
}
