# D2 검증 기록

## 전용 시각 fixture

- `RoutineFinishedFigmaVisualTests`
- 상태: regular, trial, no-streak, no-completed-steps, long-korean
- Dynamic Type: Medium, AX3
- 캔버스: 393 × 852 pt, 3x, Light
- 각 fixture를 두 번 렌더하고 크기와 PNG byte 동일성을 확인
- AX3는 font와 같은 relative style로 scale·반올림한 140% exact line-height 적용
- `main@9e89776e` Before와 rebased D2 After를 각각 다시 캡처
- 결과: 10개 상태 모두 통과, 각 primary/repeat PNG byte 동일
- line-height review 수정 전후 Medium 다섯 상태 PNG byte 동일

## 비교 산출

- regular Medium Figma↔After
- trial Medium Figma↔After
- regular, trial, no-streak, no-completed-steps, long-korean의
  Medium/AX3 Before↔After
- 결과: 12개 비교 모두 side-by-side, overlay, difference heatmap, metrics 생성
- Figma↔After mean absolute channel delta:
  regular `9.978310418608222`, trial `7.922860448800511`
- AX3 Before↔After mean absolute channel delta:
  regular `24.983450462458094`, trial `24.021909728299324`,
  no-streak `27.82027797349162`, no-completed-steps `25.070663916201564`,
  long-korean `25.06845397034823`
- primary/side-by-side PNG 크기: `1179x2556` / `2358x2556`
- 디자인 QA: P0/P1/P2 0, `final result: passed`

## 전체 회귀

- 전체 XCTest (serial): 257 passed, 0 failed, 0 skipped
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
