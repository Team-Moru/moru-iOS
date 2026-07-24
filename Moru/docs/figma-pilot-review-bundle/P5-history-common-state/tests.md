# P5 검증 기록

## 전용 시각 fixture

- `HistoryDetailFigmaVisualTests`: 2 passed, 0 failed
- 11상태 × Medium/AX3 × 2회 렌더
- raw capture 44개, 반복 PNG byte mismatch 0
- copy contract: 주간/데일리 제목, 요일별 완수율, 항목별 분석,
  오늘의 기록, 항목별 결과

## 공통 상태 회귀

- `HistoryOverviewFigmaVisualTests`: passed
- `HomeProfileFigmaVisualTests`: 2 passed
- loading, empty, error, partial-data, permission-off
- 5상태 × Medium/AX3 × 2회 렌더
- 공통 상태 반복 PNG byte mismatch 0

## 전체 회귀

- 전체 XCTest: 268 passed, 0 failed, 0 skipped
- `FinalScreenVisualTests`: 7 passed, 0 failed, 0 skipped
- iPhone 16 Simulator Debug build: passed
- generic iOS Debug build: passed
- generic iOS Release build: passed
- iPhone functional gate: passed
- SwiftData boundary gate: passed
- `Moru/Info.plist` lint: passed
- `git diff --check`: passed
- Domain/Data/schema/migration/Repository/DependencyContainer/SessionStore diff: 0
- Xcode project file diff: 0

## Pixel metrics

- 22 Before↔After comparisons 생성
- 3 Figma↔After comparisons 생성
- 모든 metrics:
  `comparedPixelCount == 2673972`,
  `maskedPixelCount == 339552`,
  `maximumChannelDelta <= 255`
- Figma↔After MAD gate: weekly ≤ 11, daily ≤ 10, run ≤ 15

```sh
jq -e '
  .width == 1179 and .height == 2556
  and .comparedPixelCount == 2673972
  and .maskedPixelCount == 339552
  and .maximumChannelDelta <= 255
' states/*/light-*/before-after/metrics.json

jq -e '.meanAbsoluteChannelDelta <= 11' figma-after/weekly/metrics.json
jq -e '.meanAbsoluteChannelDelta <= 10' figma-after/daily/metrics.json
jq -e '.meanAbsoluteChannelDelta <= 15' figma-after/run/metrics.json
```
