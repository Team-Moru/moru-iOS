//
//  ProfileCopy.swift
//  Moru
//
//  Created by Codex on 7/24/26.
//

import Foundation

nonisolated enum ProfileCopy {
  static let title = "설정"
  static let voiceSettings = "음성 설정"
  static let moruVoice = "모루 말투"
  static let account = "계정"
  static let socialLogin = "소셜 로그인"
  static let accountConnection = "계정 연결"
  static let accountConnectionDescription =
    "계정 연결은 선택 사항이에요. 취소하거나 연결에"
      + "\n실패해도 기존 루틴과 기록은 그대로 사용할 수 있어요."
  static let logout = "로그아웃"
  static let withdraw = "회원탈퇴"
  static let dataManagement = "데이터 관리"
  static let resetLocalData = "로컬 데이터 초기화"
  static let support = "고객 지원"
  static let termsOfService = "이용약관"
  static let contact = "문의하기"
  static let contactEmail = "mmoru2026@gmail.com"
  static let close = "닫기"
}

nonisolated struct ProfileSupportLinks: Equatable, Sendable {
  let termsOfServiceURL: URL?
  let contactURL: URL

  init(
    policyConfiguration: AccountEntryPolicyConfiguration,
    contactEmail: String = ProfileCopy.contactEmail
  ) {
    termsOfServiceURL = policyConfiguration.termsOfServiceURL

    var components = URLComponents()
    components.scheme = "mailto"
    components.path = contactEmail
    guard let contactURL = components.url else {
      preconditionFailure("The MORU support email must form a valid mailto URL.")
    }
    self.contactURL = contactURL
  }
}
