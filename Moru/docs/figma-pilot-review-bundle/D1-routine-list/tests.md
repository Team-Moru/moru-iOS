# D1 검증 기록

## 전용 시각 fixture

- `RoutineListFigmaVisualTests`
- 상태: normal, empty, partial-empty, alarm-warning, long-korean
- Dynamic Type: Medium, AX3
- 캔버스: 393 × 852 pt, 3x, Light
- 각 fixture를 두 번 렌더하고 픽셀 크기와 PNG byte 동일성을 확인
- `main@b5ae957f` Before와 rebased D1 After를 각각 다시 캡처
- 결과: 10개 상태 모두 통과, 각 After repeat와 byte 동일

## 비교 산출

- normal Medium Figma↔After
- normal Medium Before↔After
- normal AX3 Before↔After
- 결과: 세 비교 모두 side-by-side, overlay, difference heatmap, metrics 생성
- Figma↔After Medium mean absolute channel delta: `4.313836370263663`
- 각 primary/side-by-side PNG 크기: `1179x2556` / `2358x2556`

## 전체 회귀

- 전체 XCTest (serial): 256 passed, 0 failed, 0 skipped
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

## 시각 baseline 승인 이동

Figma↔After와 Before↔After 비교 산출물을 생성한 뒤 의도적으로 바뀐 루틴 화면만
기존 `FinalScreenVisualTests` baseline을 갱신했다.

- normal: Medium, AX3
- empty: Medium, AX3

다른 화면의 baseline과 허용 Hamming distance는 변경하지 않았다.
