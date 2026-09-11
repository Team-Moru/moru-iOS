//
//  AppFont.swift
//  Moru
//
//  Created by Codex on 7/3/26.
//

import SwiftUI

enum AppFont {
  // MARK: - Title

  static let title1Bold = Font.custom("Pretendard-Bold", size: 32)
  static let title1SemiBold = Font.custom("Pretendard-SemiBold", size: 32)
  static let title2Bold = Font.custom("Pretendard-Bold", size: 28)

  // MARK: - Heading

  static let heading1Bold = Font.custom("Pretendard-Bold", size: 22)
  static let heading3SemiBold = Font.custom("Pretendard-SemiBold", size: 18)

  // MARK: - Body

  static let body1NormalBold = Font.custom("Pretendard-Bold", size: 16)
  static let body1NormalSemiBold = Font.custom("Pretendard-SemiBold", size: 16)
  static let body1NormalMedium = Font.custom("Pretendard-Medium", size: 16)

  // MARK: - Label

  static let label1NormalSemiBold = Font.custom("Pretendard-SemiBold", size: 14)
  static let label1NormalMedium = Font.custom("Pretendard-Medium", size: 14)

  // MARK: - Caption

  static let caption1Bold = Font.custom("Pretendard-Bold", size: 12)
  static let caption1SemiBold = Font.custom("Pretendard-SemiBold", size: 12)
  static let caption1Medium = Font.custom("Pretendard-Medium", size: 12)

  // MARK: - Pretendard Weights

  static func pretendardBold(size: CGFloat) -> Font {
    Font.custom("Pretendard-Bold", size: size)
  }

  static func pretendardBold(
    size: CGFloat,
    relativeTo textStyle: Font.TextStyle
  ) -> Font {
    Font.custom("Pretendard-Bold", size: size, relativeTo: textStyle)
  }

  static func pretendardSemiBold(size: CGFloat) -> Font {
    Font.custom("Pretendard-SemiBold", size: size)
  }

  static func pretendardSemiBold(
    size: CGFloat,
    relativeTo textStyle: Font.TextStyle
  ) -> Font {
    Font.custom("Pretendard-SemiBold", size: size, relativeTo: textStyle)
  }

  static func pretendardMedium(size: CGFloat) -> Font {
    Font.custom("Pretendard-Medium", size: size)
  }

  static func pretendardMedium(
    size: CGFloat,
    relativeTo textStyle: Font.TextStyle
  ) -> Font {
    Font.custom("Pretendard-Medium", size: size, relativeTo: textStyle)
  }

  static func pretendardRegular(size: CGFloat) -> Font {
    Font.custom("Pretendard-Regular", size: size)
  }

}
