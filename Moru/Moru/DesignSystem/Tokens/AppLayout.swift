//
//  AppLayout.swift
//  Moru
//
//  Created by Codex on 7/3/26.
//

import SwiftUI

enum AppSpacing {
  static let none: CGFloat = 0
  static let xxxs: CGFloat = 2
  static let xxs: CGFloat = 4
  static let six: CGFloat = 6
  static let xs: CGFloat = 8
  static let ten: CGFloat = 10
  static let sm: CGFloat = 12
  static let md: CGFloat = 16
  static let lg: CGFloat = 20
  static let xl: CGFloat = 24
  static let twentyEight: CGFloat = 28
  static let xxl: CGFloat = 32
  static let thirtySix: CGFloat = 36
  static let forty: CGFloat = 40
  static let fortyEight: CGFloat = 48
  static let fiftySix: CGFloat = 56
  static let sixtyFour: CGFloat = 64
  static let seventyTwo: CGFloat = 72

  static let screenHorizontal: CGFloat = 20
  static let bottomCTAHorizontal: CGFloat = 20
  static let bottomCTAVertical: CGFloat = 16
  static let buttonHorizontal: CGFloat = 36
  static let buttonVertical: CGFloat = 16
  static let iconTextGap: CGFloat = 10
}

enum AppRadius {
  static let xs: CGFloat = 8
  static let sm: CGFloat = 16
  static let md: CGFloat = 16
  static let lg: CGFloat = 24
  static let xl: CGFloat = 24
  static let pill: CGFloat = 100
}

enum AppShadow {
  static let cardColor = AppColor.grayBlack.opacity(0.06)
  static let cardRadius: CGFloat = 16
  static let cardY: CGFloat = 6
}
