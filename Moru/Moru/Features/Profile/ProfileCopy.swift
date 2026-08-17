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
  static let withdrawalPending = "회원탈퇴 확인 필요"
  static let retryWithdrawal = "회원탈퇴 다시 시도"
  static let withdrawalPendingDescription =
    "이전 요청의 서버 처리 결과를 확인하지 못했어요. "
      + "다시 요청해 완료 여부를 확인해 주세요."
  static let appleWithdrawalReauthentication = "Apple로 다시 인증"
  static let appleWithdrawalReauthenticationDescription =
    "회원탈퇴를 계속하려면 Apple로 다시 인증해야 해요. "
      + "인증 전에는 계정 삭제를 완료하지 않아요."
  static let withdrawalResetUnavailable =
    "회원탈퇴 확인이 끝날 때까지 로컬 데이터를 초기화할 수 없어요."
  static let dataManagement = "데이터 관리"
  static let resetLocalData = "로컬 데이터 초기화"
  static let aiDataHandling = "AI 데이터 처리"
  static let aiDataConsentGranted = "AI 데이터 처리 동의됨"
  static let aiDataConsentNotGranted = "AI 데이터 처리에 동의하지 않았어요"
  static let aiDataConsentManage = "AI 데이터 처리 설정"
  static let aiDataConsentWithdraw = "AI 데이터 처리 동의 철회"
  static let support = "고객 지원"
  static let privacyPolicy = "개인정보처리방침"
  static let termsOfService = "이용약관"
  static let contact = "문의하기"
  static let contactEmail = "mmoru2026@gmail.com"
  static let supportLinkErrorTitle = "링크를 열 수 없어요"
  static let supportLinkConfigurationError =
    "주소 설정을 확인하지 못했어요. 잠시 후 다시 시도해 주세요."
  static func supportLinkOpenError(title: String) -> String {
    "\(title)을 열지 못했어요. 잠시 후 다시 시도해 주세요."
  }
  static let confirm = "확인"
  static let close = "닫기"
}

nonisolated struct ProfileSupportLinks: Equatable, Sendable {
  let privacyPolicyURL: URL?
  let termsOfServiceURL: URL?
  let contactURL: URL

  init(
    policyConfiguration: AccountEntryPolicyConfiguration,
    contactEmail: String = ProfileCopy.contactEmail
  ) {
    privacyPolicyURL = policyConfiguration.privacyPolicyURL
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
