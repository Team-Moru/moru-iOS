//
//  DesignSystem.swift
//  Moru
//
//  Created by Codex on 6/30/26.
//

import SwiftUI

// MARK: - App Color

enum AppColor {
  // MARK: - Baby Blue

  /// Baby Blue의 가장 연한 50 단계 컬러로, 아주 약한 배경 강조에 사용합니다.
  static let babyBlue50 = Color("babyBlue50")

  /// Baby Blue의 100 단계 컬러로, 은은한 정보성 배경에 사용합니다.
  static let babyBlue100 = Color("babyBlue100")

  /// Baby Blue의 150 단계 컬러로, 연한 보조 배경과 상태 표시에 사용합니다.
  static let babyBlue150 = Color("babyBlue150")

  /// Baby Blue의 200 단계 컬러로, 부드러운 정보성 강조에 사용합니다.
  static let babyBlue200 = Color("babyBlue200")

  /// Baby Blue의 250 단계 컬러로, 중간보다 약한 정보성 포인트에 사용합니다.
  static let babyBlue250 = Color("babyBlue250")

  /// Baby Blue의 300 단계 컬러로, 밝은 포인트 배경과 그래픽 요소에 사용합니다.
  static let babyBlue300 = Color("babyBlue300")

  /// Baby Blue의 350 단계 컬러로, 주요 정보성 포인트에 사용합니다.
  static let babyBlue350 = Color("babyBlue350")

  /// Baby Blue의 400 단계 컬러로, 활성 상태와 주요 아이콘 강조에 사용합니다.
  static let babyBlue400 = Color("babyBlue400")

  /// Baby Blue의 450 단계 컬러로, 강한 선택 상태나 링크 강조에 사용합니다.
  static let babyBlue450 = Color("babyBlue450")

  // MARK: - Coral

  /// Coral의 100 단계 컬러로, 은은한 코랄 계열 배경에 사용합니다.
  static let coral100 = Color("coral100")

  /// Coral의 150 단계 컬러로, 연한 보조 배경과 상태 표시에 사용합니다.
  static let coral150 = Color("coral150")

  /// Coral의 200 단계 컬러로, 부드러운 코랄 계열 강조에 사용합니다.
  static let coral200 = Color("coral200")

  /// Coral의 250 단계 컬러로, 중간보다 약한 코랄 포인트에 사용합니다.
  static let coral250 = Color("coral250")

  /// Coral의 300 단계 컬러로, 밝은 포인트 배경과 그래픽 요소에 사용합니다.
  static let coral300 = Color("coral300")

  // MARK: - Purple

  /// Purple의 350 단계 컬러로, 보라 계열의 밝은 강조 요소에 사용합니다.
  static let purple350 = Color("purple350")

  /// Purple의 400 단계 컬러로, 보라 계열의 주요 포인트에 사용합니다.
  static let purple400 = Color("purple400")

  /// Purple의 450 단계 컬러로, 활성 상태와 선택된 요소에 사용합니다.
  static let purple450 = Color("purple450")

  /// Purple의 500 단계 컬러로, 강한 보라 계열 강조에 사용합니다.
  static let purple500 = Color("purple500")

  /// Purple의 550 단계 컬러로, 진한 보라 계열 포인트에 사용합니다.
  static let purple550 = Color("purple550")

  /// Purple의 600 단계 컬러로, 어두운 보라 배경과 높은 대비 요소에 사용합니다.
  static let purple600 = Color("purple600")

  /// Purple의 650 단계 컬러로, 가장 진한 보라 계열 강조에 사용합니다.
  static let purple650 = Color("purple650")

  // MARK: - Gray

  /// Gray의 100 단계 컬러로, 기본 화면 배경과 연한 구분 영역에 사용합니다.
  static let gray100 = Color("gray100")

  /// Gray의 150 단계 컬러로, 보조 배경과 비활성 컨테이너에 사용합니다.
  static let gray150 = Color("gray150")

  /// Gray의 200 단계 컬러로, 약한 구분선과 비활성 상태에 사용합니다.
  static let gray200 = Color("gray200")

  /// Gray의 250 단계 컬러로, 보조 텍스트보다 약한 UI 요소에 사용합니다.
  static let gray250 = Color("gray250")

  /// Gray의 300 단계 컬러로, 플레이스홀더와 비활성 아이콘에 사용합니다.
  static let gray300 = Color("gray300")

  /// Gray의 350 단계 컬러로, 보조 텍스트와 중간 대비 아이콘에 사용합니다.
  static let gray350 = Color("gray350")

  /// Gray의 400 단계 컬러로, 일반 보조 텍스트와 구분 요소에 사용합니다.
  static let gray400 = Color("gray400")

  /// Gray의 450 단계 컬러로, 중간보다 강한 보조 정보에 사용합니다.
  static let gray450 = Color("gray450")

  /// Gray의 500 단계 컬러로, 어두운 보조 텍스트와 아이콘에 사용합니다.
  static let gray500 = Color("gray500")

  /// Gray의 550 단계 컬러로, 높은 대비가 필요한 보조 요소에 사용합니다.
  static let gray550 = Color("gray550")

  /// Gray의 600 단계 컬러로, 진한 텍스트와 어두운 표면에 사용합니다.
  static let gray600 = Color("gray600")

  /// Gray의 650 단계 컬러로, 검정에 가까운 배경과 최고 대비 요소에 사용합니다.
  static let gray650 = Color("gray650")

  /// 시스템 팔레트의 순수 검정 컬러로, 최고 대비 텍스트와 아이콘에 사용합니다.
  static let grayBlack = Color("grayBlack")

  /// 시스템 팔레트의 순수 흰색 컬러로, 어두운 배경 위 텍스트와 표면에 사용합니다.
  static let grayWhite = Color("grayWhite")

  // MARK: - Orange

  /// Orange의 100 단계 컬러로, 아주 약한 주황 배경 강조에 사용합니다.
  static let orange100 = Color("orange100")

  /// Orange의 150 단계 컬러로, 연한 배경이나 보조 강조 영역에 사용합니다.
  static let orange150 = Color("orange150")

  /// Orange의 200 단계 컬러로, 부드러운 상태 표시와 배경 강조에 사용합니다.
  static let orange200 = Color("orange200")

  /// Orange의 250 단계 컬러로, 중간보다 약한 오렌지 강조에 사용합니다.
  static let orange250 = Color("orange250")

  /// Orange의 300 단계 컬러로, 카드나 칩의 보조 포인트 컬러에 사용합니다.
  static let orange300 = Color("orange300")

  /// Orange의 350 단계 컬러로, 주요 브랜드 포인트와 액션 강조에 사용합니다.
  static let orange350 = Color("orange350")

  /// Orange의 400 단계 컬러로, 중간보다 강한 브랜드 포인트에 사용합니다.
  static let orange400 = Color("orange400")

  /// Orange의 450 단계 컬러로, 강한 선택 상태와 활성 요소에 사용합니다.
  static let orange450 = Color("orange450")

  /// Orange의 500 단계 컬러로, 주요 CTA와 핵심 강조 요소에 사용합니다.
  static let orange500 = Color("orange500")

  /// Orange의 550 단계 컬러로, 가장 진한 브랜드 강조와 높은 대비 요소에 사용합니다.
  static let orange550 = Color("orange550")
}

// MARK: - App Font

enum AppFont {
  // MARK: - Display

  /// KOR Display 1 Bold 스타일로, 가장 큰 대표 문구에 사용합니다.
  static let display1Bold = Font.custom("SUIT-Bold", size: 56)

  /// KOR Display 2 Bold 스타일로, 큰 화면 제목이나 강한 히어로 문구에 사용합니다.
  static let display2Bold = Font.custom("SUIT-Bold", size: 40)

  /// KOR Display 3 Bold 스타일로, 보조 히어로 문구와 큰 섹션 제목에 사용합니다.
  static let display3Bold = Font.custom("SUIT-Bold", size: 36)

  // MARK: - Title

  /// KOR Title 1 Bold 스타일로, 주요 화면 제목에 사용합니다.
  static let title1Bold = Font.custom("SUIT-Bold", size: 32)

  /// KOR Title 1 SemiBold 스타일로, 주요 화면 제목의 보조 강조에 사용합니다.
  static let title1SemiBold = Font.custom("SUIT-SemiBold", size: 32)

  /// KOR Title 2 Bold 스타일로, 중간 크기의 화면 제목에 사용합니다.
  static let title2Bold = Font.custom("SUIT-Bold", size: 28)

  /// KOR Title 2 SemiBold 스타일로, 중간 크기 제목의 보조 강조에 사용합니다.
  static let title2SemiBold = Font.custom("SUIT-SemiBold", size: 28)

  /// KOR Title 3 Bold 스타일로, 작은 화면 제목과 큰 섹션 제목에 사용합니다.
  static let title3Bold = Font.custom("SUIT-Bold", size: 24)

  /// KOR Title 3 SemiBold 스타일로, 작은 화면 제목의 보조 강조에 사용합니다.
  static let title3SemiBold = Font.custom("SUIT-SemiBold", size: 24)

  // MARK: - Heading

  /// KOR Heading 1 Bold 스타일로, 상위 섹션 제목에 사용합니다.
  static let heading1Bold = Font.custom("SUIT-Bold", size: 22)

  /// KOR Heading 1 SemiBold 스타일로, 상위 섹션 제목의 보조 강조에 사용합니다.
  static let heading1SemiBold = Font.custom("SUIT-SemiBold", size: 22)

  /// KOR Heading 2 Bold 스타일로, 일반 섹션 제목에 사용합니다.
  static let heading2Bold = Font.custom("SUIT-Bold", size: 20)

  /// KOR Heading 2 SemiBold 스타일로, 일반 섹션 제목의 보조 강조에 사용합니다.
  static let heading2SemiBold = Font.custom("SUIT-SemiBold", size: 20)

  /// KOR Heading 3 Bold 스타일로, 작은 섹션 제목과 강조 문구에 사용합니다.
  static let heading3Bold = Font.custom("SUIT-Bold", size: 18)

  /// KOR Heading 3 SemiBold 스타일로, 작은 섹션 제목의 보조 강조에 사용합니다.
  static let heading3SemiBold = Font.custom("SUIT-SemiBold", size: 18)

  // MARK: - Body

  /// KOR Body 1 Normal Bold 스타일로, 본문 안의 강한 강조 문구에 사용합니다.
  static let body1NormalBold = Font.custom("SUIT-Bold", size: 16)

  /// KOR Body 1 Normal SemiBold 스타일로, 본문 안의 중간 강조 문구에 사용합니다.
  static let body1NormalSemiBold = Font.custom("SUIT-SemiBold", size: 16)

  /// KOR Body 1 Normal Medium 스타일로, 기본 본문과 리스트 항목에 사용합니다.
  static let body1NormalMedium = Font.custom("SUIT-Medium", size: 16)

  // MARK: - Label

  /// KOR Label 1 Normal Bold 스타일로, 작은 버튼과 라벨의 강한 강조에 사용합니다.
  static let label1NormalBold = Font.custom("SUIT-Bold", size: 14)

  /// KOR Label 1 Normal SemiBold 스타일로, 작은 버튼과 라벨의 중간 강조에 사용합니다.
  static let label1NormalSemiBold = Font.custom("SUIT-SemiBold", size: 14)

  /// KOR Label 1 Normal Medium 스타일로, 기본 라벨과 보조 UI 텍스트에 사용합니다.
  static let label1NormalMedium = Font.custom("SUIT-Medium", size: 14)

  // MARK: - Caption

  /// KOR Caption 1 Bold 스타일로, 작은 캡션의 강한 강조에 사용합니다.
  static let caption1Bold = Font.custom("SUIT-Bold", size: 12)

  /// KOR Caption 1 SemiBold 스타일로, 작은 캡션의 중간 강조에 사용합니다.
  static let caption1SemiBold = Font.custom("SUIT-SemiBold", size: 12)

  /// KOR Caption 1 Medium 스타일로, 일반 캡션과 메타 정보에 사용합니다.
  static let caption1Medium = Font.custom("SUIT-Medium", size: 12)

  // MARK: - SUIT Weights

  /// SUIT Heavy를 원하는 크기로 사용할 때 호출합니다.
  static func suitHeavy(size: CGFloat) -> Font {
    Font.custom("SUIT-Heavy", size: size)
  }

  /// SUIT ExtraBold를 원하는 크기로 사용할 때 호출합니다.
  static func suitExtraBold(size: CGFloat) -> Font {
    Font.custom("SUIT-ExtraBold", size: size)
  }

  /// SUIT Bold를 원하는 크기로 사용할 때 호출합니다.
  static func suitBold(size: CGFloat) -> Font {
    Font.custom("SUIT-Bold", size: size)
  }

  /// SUIT SemiBold를 원하는 크기로 사용할 때 호출합니다.
  static func suitSemiBold(size: CGFloat) -> Font {
    Font.custom("SUIT-SemiBold", size: size)
  }

  /// SUIT Medium을 원하는 크기로 사용할 때 호출합니다.
  static func suitMedium(size: CGFloat) -> Font {
    Font.custom("SUIT-Medium", size: size)
  }

  /// SUIT Regular를 원하는 크기로 사용할 때 호출합니다.
  static func suitRegular(size: CGFloat) -> Font {
    Font.custom("SUIT-Regular", size: size)
  }

  /// SUIT Light를 원하는 크기로 사용할 때 호출합니다.
  static func suitLight(size: CGFloat) -> Font {
    Font.custom("SUIT-Light", size: size)
  }

  /// SUIT ExtraLight를 원하는 크기로 사용할 때 호출합니다.
  static func suitExtraLight(size: CGFloat) -> Font {
    Font.custom("SUIT-ExtraLight", size: size)
  }

  /// SUIT Thin을 원하는 크기로 사용할 때 호출합니다.
  static func suitThin(size: CGFloat) -> Font {
    Font.custom("SUIT-Thin", size: size)
  }

  // MARK: - Pretendard Weights

  /// Pretendard Black을 원하는 크기로 사용할 때 호출합니다.
  static func pretendardBlack(size: CGFloat) -> Font {
    Font.custom("Pretendard-Black", size: size)
  }

  /// Pretendard ExtraBold를 원하는 크기로 사용할 때 호출합니다.
  static func pretendardExtraBold(size: CGFloat) -> Font {
    Font.custom("Pretendard-ExtraBold", size: size)
  }

  /// Pretendard Bold를 원하는 크기로 사용할 때 호출합니다.
  static func pretendardBold(size: CGFloat) -> Font {
    Font.custom("Pretendard-Bold", size: size)
  }

  /// Pretendard SemiBold를 원하는 크기로 사용할 때 호출합니다.
  static func pretendardSemiBold(size: CGFloat) -> Font {
    Font.custom("Pretendard-SemiBold", size: size)
  }

  /// Pretendard Medium을 원하는 크기로 사용할 때 호출합니다.
  static func pretendardMedium(size: CGFloat) -> Font {
    Font.custom("Pretendard-Medium", size: size)
  }

  /// Pretendard Regular를 원하는 크기로 사용할 때 호출합니다.
  static func pretendardRegular(size: CGFloat) -> Font {
    Font.custom("Pretendard-Regular", size: size)
  }

  /// Pretendard Light를 원하는 크기로 사용할 때 호출합니다.
  static func pretendardLight(size: CGFloat) -> Font {
    Font.custom("Pretendard-Light", size: size)
  }

  /// Pretendard ExtraLight를 원하는 크기로 사용할 때 호출합니다.
  static func pretendardExtraLight(size: CGFloat) -> Font {
    Font.custom("Pretendard-ExtraLight", size: size)
  }

  /// Pretendard Thin을 원하는 크기로 사용할 때 호출합니다.
  static func pretendardThin(size: CGFloat) -> Font {
    Font.custom("Pretendard-Thin", size: size)
  }
}

// MARK: - App Icon

enum AppIcon {
  // MARK: - Navigation

  /// 홈 탭과 메인 화면 이동에 사용하는 아이콘입니다.
  static let iconHome = "iconHome"

  /// 루틴 탭과 루틴 관련 화면 이동에 사용하는 아이콘입니다.
  static let iconRoutine = "iconRoutine"

  /// 입력 탭과 기록 입력 화면 이동에 사용하는 아이콘입니다.
  static let iconInput = "iconInput"

  /// 설정 탭과 환경설정 화면 이동에 사용하는 아이콘입니다.
  static let iconSettings = "iconSettings"

  // MARK: - Communication

  /// 기본 알림 상태를 나타내는 벨 아이콘입니다.
  static let iconBell = "iconBell"

  /// 활성화되었거나 울리는 알림 상태를 나타내는 벨 아이콘입니다.
  static let iconBellRing = "iconBellRing"

  // MARK: - Environment

  /// 커피나 따뜻한 음료 관련 기능에 사용하는 아이콘입니다.
  static let iconCoffee = "iconCoffee"

  /// 밤, 수면, 저녁 루틴을 나타낼 때 사용하는 달 아이콘입니다.
  static let iconMoon = "iconMoon"

  /// 낮, 아침, 밝은 상태를 나타낼 때 사용하는 해 아이콘입니다.
  static let iconSun = "iconSun"

  /// 물, 수분, 습도 관련 기능에 사용하는 물방울 아이콘입니다.
  static let iconWaterDrop = "iconWaterDrop"

  // MARK: - Media

  /// 오디오 청취나 헤드폰 관련 기능에 사용하는 아이콘입니다.
  static let iconHeadphones = "iconHeadphones"

  /// 이미지 또는 사진 관련 기능에 사용하는 아이콘입니다.
  static let iconImage = "iconImage"

  /// 정지, 중단, 기록 종료 같은 상태에 사용하는 원형 정지 아이콘입니다.
  static let iconStopCircle = "iconStopCircle"

  /// 볼륨이 큰 상태나 소리 관련 기능에 사용하는 아이콘입니다.
  static let iconVolumeMax = "iconVolumeMax"

  // MARK: - Menu

  /// 메뉴 열기나 더보기 내비게이션에 사용하는 햄버거 아이콘입니다.
  static let iconHamburger = "iconHamburger"

  // MARK: - User

  /// 단일 사용자나 프로필을 나타낼 때 사용하는 아이콘입니다.
  static let iconUser = "iconUser"

  /// 원형 프로필 또는 계정 상태를 나타낼 때 사용하는 사용자 아이콘입니다.
  static let iconUserCircle = "iconUserCircle"

  /// 여러 사용자나 그룹을 나타낼 때 사용하는 아이콘입니다.
  static let iconUsers = "iconUsers"
}

// MARK: - Design System Preview

struct DesignSystemPreview: View {
  var body: some View {
    ZStack {
      AppColor.gray100
        .ignoresSafeArea()

      VStack(alignment: .leading, spacing: 12) {
        Text("Design System")
          .font(AppFont.title1Bold)
          .foregroundStyle(AppColor.grayBlack)

        Text("Body 1 Normal Medium 16")
          .font(AppFont.body1NormalMedium)
          .foregroundStyle(AppColor.gray650)

        Text("Caption 1 Medium 12")
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.gray400)

        Text("Primary Action")
          .font(AppFont.body1NormalSemiBold)
          .foregroundStyle(AppColor.grayWhite)
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(AppColor.orange350)
          .clipShape(RoundedRectangle(cornerRadius: 8))

        Image(AppIcon.iconBell)
          .renderingMode(.template)
          .foregroundStyle(AppColor.orange500)
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

#Preview("Design System") {
  DesignSystemPreview()
}
