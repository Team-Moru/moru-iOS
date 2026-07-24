# D0 검증 기록

## 환경

- macOS `26.5.1` (`25F80`)
- Xcode `26.5` (`17F42`)
- iOS Simulator `26.5`
- `MORU Figma iPhone 16`, 393×852pt
- `ko_KR`, `Asia/Seoul`, Light
- Medium, AX3
- PNG scale 3, 1179×2556px
- Gregorian calendar, fixed clock `2026-07-24 06:15 KST`
- animations disabled, Core Animation layer capture

## 완료

- `FigmaPilotFoundationTests`: 5 passed, 0 failed, 0 skipped.
- 전체 XCTest: 255 passed, 0 failed, 0 skipped.
- `FinalScreenVisualTests`: 7 passed, 0 failed, 0 skipped.
- 같은 After를 두 번 렌더한 PNG data가 Medium/AX3에서 byte-identical.
- 비교 CLI 동일 이미지 검사: differing pixel `0`, MAE `0`, RMSE `0`.
- iPhone 16 Simulator Debug build: passed.
- Generic iPhone Debug build: passed.
- Generic iPhone Release build: passed.
- `Scripts/check-iphone-functional-gate.sh`: passed.
- `Scripts/check-swiftdata-boundary.sh`: passed.
- `Info.plist` validation: passed.
- Domain/Data/App boundary diff: no changed files.
- Figma API version gate: `2379679754802507594`.
- `origin/main` gate: `53a2c6d24bc449f816f069dce8a558af40e15006`.

## 자체 리뷰

- 공용 컴포넌트의 기본값은 모두 `.legacy`이며 기존 initializer 호출이
  source-compatible한 것을 테스트로 확인했습니다.
- D0 제외 범위인 Domain, Data, SwiftData schema/migration,
  `DependencyContainer`, `SessionStore` 변경은 없습니다.
- component board에는 시스템 chrome이 없으므로 전체 1179×2556px를 mask 0으로
  비교했고, 저장된 JSON과 ledger가 같은 수치를 가리키는지 재확인했습니다.
- project 파일의 수동 변경과 기존 visual hash 변경은 없습니다.
