# P4 검증 기록

## 시각 회귀

- `RoutinePlayerFigmaVisualTests`: pass
  - preset/fallback/구조화 copy
  - 12개 상태 × Medium/AX3 × 2회
  - 48개 PNG, 반복 결과 byte-identical
- `RoutineFinishedFigmaVisualTests`: pass
  - 5개 상태 × Medium/AX3 × 2회
  - 20개 PNG, 반복 결과 byte-identical

## 자동 검증

- 전체 XCTest: 266 passed, 0 failed, 0 skipped
- P3/P4 시각 회귀 재검증: 4 passed, 0 failed, 0 skipped
- iPhone 16 simulator Debug build: passed
- generic iOS device Debug build: passed
- generic iOS device Release build: passed
- `Scripts/check-iphone-functional-gate.sh`: passed
- `Scripts/check-swiftdata-boundary.sh`: passed
- `plutil -lint Moru/Info.plist`: passed
- `git diff --check`: passed

첫 parallel 전체 실행에서 P3 delete dialog baseline이 변경된 유효한
회귀를 발견했다. 공통 `MoruDialog`의 기존 render를 default로 복구하고
P4 Skip/End만 adaptive variant를 opt-in하도록 scope를 분리했다. 이후
P3/P4 단독 4개와 전체 266개를 serial로 재실행해 모두 통과했다.
