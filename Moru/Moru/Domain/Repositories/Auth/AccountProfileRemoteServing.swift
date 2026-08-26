//
//  AccountProfileRemoteServing.swift
//  Moru
//

import Foundation

/// 로그인한 회원의 계정 정보(프로필, 스트릭) 조회.
///
/// `ServerAccountProfile`은 `selectedTTSID`를 포함하므로 Voice 계층도 이 계약을
/// 통해 회원의 선택 음성을 읽는다. 서버 응답 형태에서 온 결합이라 프로필 조회를
/// Voice 쪽으로 옮기거나 Auth 쪽에서 떼어내는 방식으로는 해소되지 않는다.
nonisolated protocol AccountProfileRemoteServing: Sendable {
  func fetchProfile(memberID: Int64) async throws -> ServerAccountProfile
  func fetchStreak(memberID: Int64) async throws -> ServerAccountStreak
}

nonisolated enum AccountServerRemoteError:
  Error,
  Equatable,
  Sendable {
  case invalidRequest
  case invalidResponse
  case accountAuthorizationChanged
}
