//
//  OnboardingProgressStoring.swift
//  Moru
//

import Foundation

/// 온보딩 체험을 끝내고 계정 연결 화면을 아직 보지 못한 상태를 앱 실행 사이에 남긴다.
///
/// 이 한 가지만 영속한다. 체험 도중 앱이 죽으면 프로필은 이미 저장돼 있어
/// 루트가 곧장 홈으로 가 버리고, 사용자는 계정 연결 화면을 영영 보지 못했다.
/// 나머지 루트 전이 플래그는 한 번의 실행 안에서만 의미가 있어 남기지 않는다.
@MainActor
protocol OnboardingProgressStoring: AnyObject {
  var isAccountEntryPending: Bool { get }

  func setAccountEntryPending(_ isPending: Bool)
}
