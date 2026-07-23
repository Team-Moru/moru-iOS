# Figma 파일럿 공통 기반

이 문서는 Figma 세부 보정 파일럿에서만 선택적으로 쓰는 token, typography,
공용 컴포넌트 스타일, 캡처 fixture와 비교 도구를 설명합니다.

기준 Figma file version은 `2379548990233618412`입니다.

## Opt-in token

기존 화면은 `AppColor`, `AppSpacing`, `AppRadius`, `AppFont`를 계속 사용합니다.
파일럿 화면만 아래 API를 명시적으로 선택합니다.

```swift
MoruPilotColor.canvas
MoruPilotColor.accent
MoruPilotSpacing.twenty
MoruPilotRadius.largeCard
```

## Typography

`MoruTextStyle`은 Figma의 D1~C2 size와 140% line height를 제공합니다.
각 preset은 기본 weight를 가지며 필요한 경우 weight만 바꿀 수 있습니다.

```swift
Text("활력 루틴")
  .moruTextStyle(.b3.weight(.semiBold))
```

기존 `AppFont` API는 변경하지 않았습니다.

## 공용 컴포넌트

기존 initializer의 기본값은 `.legacy`입니다. 파일럿에서만
`componentStyle: .figmaPilot`을 전달합니다.

```swift
MoruRoutineCard(
  title: "활력 루틴",
  description: "6개 항목 ・15분",
  isActive: $isActive,
  componentStyle: .figmaPilot
)
```

같은 opt-in parameter를 다음 컴포넌트에서 사용할 수 있습니다.

- `MoruProgressBar`
- `MoruToggle`
- `MoruTabBar`
- `MoruButton`
- `MoruRoutineCard`

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

다음 결과를 생성합니다.

- `side-by-side.png`
- `overlay.png` — reference/candidate 50% 합성
- `difference-heatmap.png` — absolute channel delta 기반 heatmap
- `metrics.json` — differing pixels, MAE, RMSE, maximum delta

마스크 값은 3× PNG의 pixel 단위입니다. 앱이 그리지 않는 상태바와
home indicator 영역을 metric과 heatmap에서 제외할 때 사용합니다.
