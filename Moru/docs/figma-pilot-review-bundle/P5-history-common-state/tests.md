# P5 검증 기록

## 전용 시각 fixture

- `HistoryDetailFigmaVisualTests`: 2 passed, 0 failed
- 11상태 × Medium/AX3 × 2회 렌더
- raw capture 44개, 반복 PNG byte mismatch 0
- copy contract: 주간/데일리 제목, 요일별 완수율, 항목별 분석,
  오늘의 기록, 항목별 결과
- weekly Medium: summary 제목→값 순서와 요일 bar의
  상단 coral→하단 투명 gradient 확인
- weekly AX3: summary 값→제목 reflow와 긴 한국어 clipping 없음 확인

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
  `maskedPixelCount == 339552`
- `maximumChannelDelta <= 255`는 8-bit 입력 범위 invariant이며 품질 gate가 아니다.
- Figma↔After MAD / differing pixel gate:
  weekly ≤ 11 / 56%, daily ≤ 11 / 74%, run ≤ 15 / 74%
- 공통 상태 quality gate: 동일 fixture 2회 PNG byte mismatch 0

```sh
jq -e '
  .width == 1179 and .height == 2556
  and .comparedPixelCount == 2673972
  and .maskedPixelCount == 339552
' states/*/light-*/before-after/metrics.json

jq -e '
  .meanAbsoluteChannelDelta <= 11
  and .differingPixelPercentage <= 56
' figma-after/weekly/metrics.json
jq -e '
  .meanAbsoluteChannelDelta <= 11
  and .differingPixelPercentage <= 74
' figma-after/daily/metrics.json
jq -e '
  .meanAbsoluteChannelDelta <= 15
  and .differingPixelPercentage <= 74
' figma-after/run/metrics.json
```
