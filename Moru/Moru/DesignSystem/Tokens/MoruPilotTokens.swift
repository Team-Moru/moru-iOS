//
//  MoruPilotTokens.swift
//  Moru
//
//  Created by Codex on 7/24/26.
//

import SwiftUI

/// Opt-in aliases for the Figma detail-correction pilot.
///
/// Existing `AppColor`, `AppSpacing`, and `AppRadius` call sites intentionally
/// remain unchanged. Pilot screens select these aliases explicitly.
enum MoruPilotColor {
  static let canvas = AppColor.babyBlue50
  static let accent = AppColor.orange350
  static let accentSoft = AppColor.orange300
  static let accentTint = AppColor.orange150
  static let accentSurface = AppColor.orange100
  static let progressTrack = Color(
    red: 246 / 255,
    green: 248 / 255,
    blue: 250 / 255
  )
  static let border = AppColor.gray150
  static let textStrong = AppColor.gray500
  static let textPrimary = AppColor.gray450
  static let textSecondary = AppColor.gray350
  static let textTertiary = AppColor.gray300
  static let shadow = Color(
    red: 216 / 255,
    green: 227 / 255,
    blue: 255 / 255
  )
}

enum MoruPilotSpacing {
  static let four: CGFloat = 4
  static let eight: CGFloat = 8
  static let ten: CGFloat = 10
  static let twelve: CGFloat = 12
  static let sixteen: CGFloat = 16
  static let twenty: CGFloat = 20
  static let thirtyTwo: CGFloat = 32
  static let thirtySix: CGFloat = 36
  static let sixtyFour: CGFloat = 64
}

enum MoruPilotRadius {
  static let card: CGFloat = 16
  static let largeCard: CGFloat = 24
  static let pill: CGFloat = 100
}

enum MoruPilotComponentStyle: Equatable {
  case legacy
  case figmaPilot
}
