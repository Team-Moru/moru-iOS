# Figma 파일럿 공통 기반

이 문서는 앱이 쓰는 시맨틱 토큰, typography, 공용 컴포넌트 스타일, 캡처 fixture와
비교 도구를 설명합니다.

기준 Figma file version은 `2379679754802507594`입니다.

## 시맨틱 토큰

화면은 팔레트(`AppColor.gray500` 같은 값 이름) 대신 시맨틱 토큰을 씁니다. 값의 단일
출처는 `AppColor` 팔레트이고, 간격·모서리는 `AppSpacing`·`AppRadius`를 alias합니다.

```swift
MoruPilotColor.canvas        // 화면 배경
MoruPilotColor.accent        // 브랜드 강조 (탭 선택, 진행 바, 활성 카드 틴트)
MoruPilotColor.ctaFill       // 주요 CTA 채움 (흰 글자 대비 4.5:1 이상)
MoruPilotColor.textStrong    // 제목
MoruPilotColor.textPrimary   // 본문
MoruPilotColor.textSecondary // 보조 텍스트
MoruPilotColor.disabled      // 비활성 채움
MoruPilotColor.link          // 링크·시스템 파란 액션
MoruPilotSpacing.twenty
MoruPilotRadius.largeCard
```

예전 `AppColor.moruText*`, `moruBorder`, `moruDisabled`, `moruSurfaceMuted`, `moruBlue`
시맨틱 이름은 제거되었습니다. 같은 값이 위 토큰에 있습니다.

## Typography

`MoruTextStyle`은 Figma의 D1~C2 size와 140% line height를 제공합니다.
각 preset은 기본 weight를 가지며 필요한 경우 weight만 바꿀 수 있습니다.

```swift
Text("활력 루틴")
  .moruTextStyle(.b3.weight(.semiBold))
```

기존 `AppFont` API는 변경하지 않았습니다.

## 공용 컴포넌트

공용 컴포넌트(`MoruButton`, `MoruProgressBar`, `MoruToggle`, `MoruTabBar`,
`MoruRoutineCard`)는 Figma 파일럿 외형을 기본값으로 사용합니다. 예전의
`componentStyle: .legacy / .figmaPilot` opt-in 파라미터는 제거되었습니다.

```swift
MoruRoutineCard(
  title: "활력 루틴",
  description: "6개 항목 ・15분",
  isActive: $isActive
)
```

## 결정적 캡처 fixture

`MoruVisualCaptureFixture`는 test target의 `MoruTests/Support`에 있습니다.
기본 환경은 다음과 같습니다.

- 393×852pt, scale 3, 1179×2556px
- `ko_KR`, `Asia/Seoul`, Gregorian calendar
- Light UI
- Medium, AX3
- 2026-07-24 06:15 KST의 고정 clock 입력
- animation 비활성화와 Core Animation layer capture

출력 위치는 `MORU_CAPTURE_OUTPUT_DIR` 환경 변수로 바꿀 수 있습니다.

## 비교 도구

`Scripts/figma-visual-compare.swift`는 AppKit으로 PNG를 읽고 쓰며,
CoreGraphics sRGB RGBA8 buffer에서 비교합니다.

```bash
xcrun swift Scripts/figma-visual-compare.swift \
  --reference /path/to/figma.png \
  --candidate /path/to/after.png \
  --output-dir /path/to/comparison \
  --mask-top-pixels 177 \
  --mask-bottom-pixels 102
```

Bottom sheet나 dialog처럼 배경 fixture가 다른 컴포넌트는 좌상단 기준 pixel
ROI와 MAE gate를 함께 지정할 수 있습니다.

```bash
xcrun swift Scripts/figma-visual-compare.swift \
  --reference /path/to/figma.png \
  --candidate /path/to/after.png \
  --output-dir /path/to/comparison \
  --compare-rect-pixels 0,1500,1179,954 \
  --maximum-mae 8
```

다음 결과를 생성합니다.

- `side-by-side.png`
- `overlay.png` — reference/candidate 50% 합성
- `difference-heatmap.png` — absolute channel delta 기반 heatmap
- `metrics.json` — differing pixels, MAE, RMSE, maximum delta

마스크 값은 3× PNG의 pixel 단위입니다. 앱이 그리지 않는 상태바와
home indicator 영역을 metric과 heatmap에서 제외할 때 사용합니다.
`--compare-rect-pixels`는 지정한 영역 밖을 metric과 heatmap에서 제외하고,
`--maximum-mae`는 결과를 쓴 뒤 기준 초과 시 non-zero로 종료합니다.
마스크와 ROI가 비교 픽셀을 하나도 남기지 않으면 잘못된 통과 대신 오류로
종료합니다.
