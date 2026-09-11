//
//  MoruTokens.swift
//  Moru
//
//  Created by Codex on 7/24/26.
//

import SwiftUI

/// 화면이 쓰는 시맨틱 색 토큰. 값의 단일 출처는 `AppColor` 팔레트다.
enum MoruColor {
  static let canvas = AppColor.babyBlue50

  // MARK: - Accent

  /// 브랜드 강조. 탭 선택, 진행 바, 활성 카드 틴트에 쓴다.
  static let accent = AppColor.orange350
  static let accentSoft = AppColor.orange300
  static let accentTint = AppColor.orange150
  static let accentSurface = AppColor.orange100
  static let summarySurface = AppColor.orange250

  /// 주요 CTA 채움. 흰 글자 기준 대비 4.5:1 이상을 유지하기 위해 accent보다 진하다.
  static let ctaFill = AppColor.orange550
  /// ctaFill 위의 글자·아이콘 색.
  static let onCTA = AppColor.grayWhite

  // MARK: - Surface

  static let profileSurface = Color(
    red: 245 / 255,
    green: 248 / 255,
    blue: 252 / 255
  )
  static let progressTrack = Color(
    red: 246 / 255,
    green: 248 / 255,
    blue: 250 / 255
  )
  static let surfaceMuted = AppColor.gray100
  static let border = AppColor.gray150
  static let disabled = AppColor.gray250
  static let shadow = Color(
    red: 216 / 255,
    green: 227 / 255,
    blue: 255 / 255
  )
  static let tabBarShadow = Color(
    red: 2 / 255,
    green: 24 / 255,
    blue: 100 / 255
  ).opacity(0.05)

  // MARK: - Text

  static let textStrong = AppColor.gray500
  static let textPrimary = AppColor.gray450
  static let textSecondary = AppColor.gray350
  static let textTertiary = AppColor.gray300

  // MARK: - Link

  static let link = AppColor.babyBlue450
  static let linkDisabled = AppColor.babyBlue250
}

/// 간격 토큰. 값은 `AppSpacing`과 같은 출처를 쓴다.
enum MoruSpacing {
  static let four = AppSpacing.xxs
  static let eight = AppSpacing.xs
  static let ten = AppSpacing.ten
  static let twelve = AppSpacing.sm
  static let sixteen = AppSpacing.md
  static let twenty = AppSpacing.lg
  static let twentyEight = AppSpacing.twentyEight
  static let thirtyTwo = AppSpacing.xxl
  static let thirtySix = AppSpacing.thirtySix
  static let thirtyEight: CGFloat = 38
  static let sixtyFour = AppSpacing.sixtyFour

  /// 화면·시트 루트의 좌우 거터. 값의 단일 출처는 `AppSpacing.screenHorizontal`이다.
  static let gutter = AppSpacing.screenHorizontal
}

/// 모서리 토큰. 값은 `AppRadius`와 같은 출처를 쓴다.
enum MoruRadius {
  static let chip = AppRadius.xs
  static let small: CGFloat = 12
  static let card = AppRadius.sm
  static let largeCard = AppRadius.lg
  static let pill = AppRadius.pill
}
