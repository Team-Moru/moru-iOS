# P4 검증 기록

## 시각 회귀

- `RoutinePlayerFigmaVisualTests`: pass
  - preset/fallback/구조화 copy
  - 12개 상태 × Medium/AX3 × 2회
  - 48개 PNG, 반복 결과 byte-identical
  - checked-in approved After baseline과 perceptual hash distance `<= 24`
- `RoutineFinishedFigmaVisualTests`: pass
  - 5개 상태 × Medium/AX3 × 2회
  - 20개 PNG, 반복 결과 byte-identical

## 자동 검증

- 전체 XCTest: 266 passed, 0 failed, 0 skipped
- P3/P4/D2 시각 회귀 재검증: 5 passed, 0 failed, 0 skipped
- iPhone 16 simulator Debug build: passed
- generic iOS device Debug build: passed
- generic iOS device Release build: passed
- `Scripts/check-iphone-functional-gate.sh`: passed
- `Scripts/check-swiftdata-boundary.sh`: passed
- `plutil -lint Moru/Info.plist`: passed
- `git diff --check`: passed

CodeRabbit 후속 검토에서 adaptive dialog button row의 가변 높이,
AX Dynamic Type의 Skip/End dialog 위치, transcript accessibility label,
approved visual baseline assertion을 보강했다. 표시용 timer duration을
active segment 계산에서 다시 파싱하지 않도록 명시적 초 단위 값으로
분리했다. P4의 Dynamic Type-aware Pretendard 선언은 동일한
`relativeTo` semantics를 제공하는 `AppFont` overload로 중앙화했다.
변경된 Skip/End AX3 After baseline도 같은 환경에서 다시 캡처하고
육안 검토했다.

첫 parallel 전체 실행에서 P3 delete dialog baseline이 변경된 유효한
회귀를 발견했다. 공통 `MoruDialog`의 기존 render를 default로 복구하고
P4 Skip/End만 adaptive variant를 opt-in하도록 scope를 분리했다. 이후
P3/P4 단독 4개와 전체 266개를 serial로 재실행해 모두 통과했다.
