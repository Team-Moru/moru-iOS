# P3 루틴 관리 검증

## 결정적 시각 캡처

- `RoutineManagementFigmaVisualTests`
  - 12상태 × Medium/AX3 × repeat = 48 PNG
  - 393 × 852 pt, scale 3, Light, `ko_KR`, `Asia/Seoul`
  - repeat PNG byte-identical
  - 24개 상태/variant 승인 perceptual dHash와 Hamming distance ≤ 24
    회귀 assertion
- exact copy/formatter:
  - `새 루틴 추가하기`
  - `새 항목 추가하기`
  - 생성 `완료`, 편집 `저장`
  - `6개 항목 ・15분`
  - `월 화 수 목 금・09시 00분`
  - `수요일로 알림이 설정된…`

## 비교 산출물

- Before/After 24쌍: side-by-side, overlay, heatmap, metrics
- Figma/After canonical Medium 9쌍: side-by-side, overlay, heatmap, metrics
- 모든 metrics:
  - `comparedPixelCount == 2673972`
  - `maskedPixelCount == 339552`

## 자동 검증

- Full XCTest: **264 passed / 0 failed / 0 skipped**
  - xcresult: `/private/tmp/moru-figma-p3-full-review-70.xcresult`
- Review follow-up targeted visual/copy: **2 passed / 0 failed**
  - xcresult: `/private/tmp/moru-p3-review-targeted.xcresult`
- `FinalScreenVisualTests`: **7 passed**
- iPhone 16 Simulator Debug build: passed
- generic iOS Simulator Debug build: passed
- generic iOS Simulator Release build: passed
- `bash Scripts/check-iphone-functional-gate.sh`: passed
- `bash Scripts/check-swiftdata-boundary.sh`: passed
- `plutil -lint Moru/Info.plist`: passed
- `git diff --check`: passed
- 금지 경로와 `Moru.xcodeproj` diff: 0

XCTest 실행 중 병렬 clone Simulator의 일시적인 launch retry 로그가 있었지만
`xcodebuild`는 0으로 종료했고 xcresult 최종 판정은 `Passed`다.
