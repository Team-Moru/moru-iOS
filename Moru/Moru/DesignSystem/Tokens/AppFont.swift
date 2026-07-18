
import SwiftUI

enum AppFont {
  // MARK: - Display

  static let display1Bold = Font.custom("Pretendard-Bold", size: 56, relativeTo: .largeTitle)
  static let display2Bold = Font.custom("Pretendard-Bold", size: 40, relativeTo: .largeTitle)
  static let display3Bold = Font.custom("Pretendard-Bold", size: 36, relativeTo: .largeTitle)

  // MARK: - Title

  static let title1Bold = Font.custom("Pretendard-Bold", size: 32, relativeTo: .largeTitle)
  static let title1SemiBold = Font.custom("Pretendard-SemiBold", size: 32, relativeTo: .largeTitle)
  static let title2Bold = Font.custom("Pretendard-Bold", size: 28, relativeTo: .title)
  static let title2SemiBold = Font.custom("Pretendard-SemiBold", size: 28, relativeTo: .title)
  static let title3Bold = Font.custom("Pretendard-Bold", size: 24, relativeTo: .title2)
  static let title3SemiBold = Font.custom("Pretendard-SemiBold", size: 24, relativeTo: .title2)

  // MARK: - Heading

  static let heading1Bold = Font.custom("Pretendard-Bold", size: 22, relativeTo: .title2)
  static let heading1SemiBold = Font.custom("Pretendard-SemiBold", size: 22, relativeTo: .title2)
  static let heading2Bold = Font.custom("Pretendard-Bold", size: 20, relativeTo: .title3)
  static let heading2SemiBold = Font.custom("Pretendard-SemiBold", size: 20, relativeTo: .title3)
  static let heading3Bold = Font.custom("Pretendard-Bold", size: 18, relativeTo: .headline)
  static let heading3SemiBold = Font.custom("Pretendard-SemiBold", size: 18, relativeTo: .headline)

  // MARK: - Body

  static let body1NormalBold = Font.custom("Pretendard-Bold", size: 16, relativeTo: .body)
  static let body1NormalSemiBold = Font.custom("Pretendard-SemiBold", size: 16, relativeTo: .body)
  static let body1NormalMedium = Font.custom("Pretendard-Medium", size: 16, relativeTo: .body)

  // MARK: - Label

  static let label1NormalBold = Font.custom("Pretendard-Bold", size: 14, relativeTo: .subheadline)
  static let label1NormalSemiBold = Font.custom(
    "Pretendard-SemiBold",
    size: 14,
    relativeTo: .subheadline
  )
  static let label1NormalMedium = Font.custom(
    "Pretendard-Medium",
    size: 14,
    relativeTo: .subheadline
  )

  // MARK: - Caption

  static let caption1Bold = Font.custom("Pretendard-Bold", size: 12, relativeTo: .caption)
  static let caption1SemiBold = Font.custom("Pretendard-SemiBold", size: 12, relativeTo: .caption)
  static let caption1Medium = Font.custom("Pretendard-Medium", size: 12, relativeTo: .caption)

  // MARK: - Pretendard Weights

  static func pretendardBlack(size: CGFloat) -> Font {
    Font.custom("Pretendard-Black", size: size)
  }

  static func pretendardExtraBold(size: CGFloat) -> Font {
    Font.custom("Pretendard-ExtraBold", size: size)
  }

  static func pretendardBold(size: CGFloat) -> Font {
    Font.custom("Pretendard-Bold", size: size)
  }

  static func pretendardSemiBold(size: CGFloat) -> Font {
    Font.custom("Pretendard-SemiBold", size: size)
  }

  static func pretendardMedium(size: CGFloat) -> Font {
    Font.custom("Pretendard-Medium", size: size)
  }

  static func pretendardRegular(size: CGFloat) -> Font {
    Font.custom("Pretendard-Regular", size: size)
  }

  static func pretendardLight(size: CGFloat) -> Font {
    Font.custom("Pretendard-Light", size: size)
  }

  static func pretendardExtraLight(size: CGFloat) -> Font {
    Font.custom("Pretendard-ExtraLight", size: size)
  }

  static func pretendardThin(size: CGFloat) -> Font {
    Font.custom("Pretendard-Thin", size: size)
  }
}
