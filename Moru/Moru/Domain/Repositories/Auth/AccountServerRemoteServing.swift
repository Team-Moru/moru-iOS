//
//  AccountServerRemoteServing.swift
//  Moru
//

import Foundation

/// 회원 계정 서버 API의 전체 계약.
///
/// Auth(`AccountProfileRemoteServing`)와 Voice(`AccountVoiceRemoteServing`)
/// 두 도메인을 합성한 형태다. 현재 소비처는 두 곳 모두 양쪽 절반을 함께
/// 사용하므로 이 합성 계약에 의존한다. 한쪽 절반만 필요한 소비처가 생기면
/// 해당 도메인 프로토콜에만 의존하도록 좁힐 수 있다.
nonisolated protocol AccountServerRemoteServing:
  AccountProfileRemoteServing,
  AccountVoiceRemoteServing {}
