# D3 검증 기록

## 전용 시각 fixture

- `HistoryOverviewFigmaVisualTests`
- 상태: regular, loading, empty, failure, partial-data, trial, no-streak,
  long-korean
- Dynamic Type: Medium, AX3
- 캔버스: 393 × 852 pt, 3x, Light, `ko_KR`, `Asia/Seoul`
- 각 fixture를 두 번 렌더하고 크기, scale, PNG byte 동일성을 확인
- 결과: 16개 상태/variant 모두 통과

## 비교 산출

- 모든 8상태 × Medium/AX3 Before↔After
- regular Medium Figma `1851:3687` ↔ After
- loading Medium Figma `2562:3611` ↔ After
- 결과: 18개 비교 모두 side-by-side, overlay, difference heatmap, metrics 생성
- Overview Figma↔After mean absolute channel delta: `7.809242081318229`
- Skeleton Figma↔After mean absolute channel delta: `3.655436307236326`

## Pixel gate

- raw capture: 1179 × 2556 px, fixture 반복 PNG byte 일치
- mask: top 186 px + bottom 102 px
- metrics invariant:
  `comparedPixelCount == 2673972`, `maskedPixelCount == 339552`,
  `maximumChannelDelta <= 255`
- Figma/After threshold: regular mean absolute channel delta ≤ 10,
  loading mean absolute channel delta ≤ 5
- Before/After metrics는 의도적 redesign의 change ledger이며 similarity threshold가 아니다.
  전체 differing pixel 범위는 `91.4822%...99.9213%`이고, 큰 diff의 상태별 근거는
  `design-qa.md`에 기록했다.

```sh
jq -e '
  .width == 1179 and .height == 2556
  and .comparedPixelCount == 2673972
  and .maskedPixelCount == 339552
  and .maximumChannelDelta <= 255
' states/*/light-*/before-after/metrics.json
jq -e '.meanAbsoluteChannelDelta <= 10' \
  states/regular/light-M/figma-after/metrics.json
jq -e '.meanAbsoluteChannelDelta <= 5' \
  states/loading/light-M/figma-after/metrics.json
```

## 전체 회귀

- 전체 XCTest: 258 passed, 0 failed, 0 skipped
- `FinalScreenVisualTests`: 7 passed, 0 failed
- iPhone 16 Simulator Debug build: passed
- generic iOS Debug build: passed
- generic iOS Release build: passed
- iPhone functional gate: passed
- SwiftData boundary gate: passed
- `Info.plist` lint: passed
- `git diff --check`: passed
- Domain/Data/schema/migration/Repository/DependencyContainer/SessionStore diff: 0
- Xcode project file diff: 0
- History AX3 승인 visual hash는 비교 이미지 육안 검토 뒤 새 responsive layout으로 갱신

## 실행 명령

```sh
xcodebuild test -project Moru/Moru.xcodeproj -scheme Moru \
  -destination 'platform=iOS Simulator,id=6FB37447-684F-4A13-A9DA-A536D22CBE9A' \
  -parallel-testing-enabled NO
xcodebuild build -project Moru/Moru.xcodeproj -scheme Moru \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=6FB37447-684F-4A13-A9DA-A536D22CBE9A'
xcodebuild build -project Moru/Moru.xcodeproj -scheme Moru \
  -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Moru/Moru.xcodeproj -scheme Moru \
  -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
bash Scripts/check-iphone-functional-gate.sh
bash Scripts/check-swiftdata-boundary.sh
plutil -lint Moru/Info.plist
git diff --check
```
