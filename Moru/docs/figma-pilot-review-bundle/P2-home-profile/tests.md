# P2 검증 기록

## 완료

- exact-base Before fixture: 14 states × Medium/AX3 × repeat, 56 PNG
- final After fixture: 14 states × Medium/AX3 × repeat, 56 PNG
- `HomeProfileFigmaVisualTests`: copy contract와 결정론 capture 2 tests 통과
- Before/After comparator: 28 sets
- Figma/After comparator: 3 canonical Medium sets
- Medium canonical 3장과 AX3 long-Korean을 combined image로 직접 검토
- Home, Profile, current routine, active routine, empty Home의 변경된
  `FinalScreenVisualTests` image를 직접 검토하고 승인 hash를 갱신

## 최종 gate

- `FinalScreenVisualTests`: 7 tests, failed 0, skipped 0
- 전체 XCTest: 262 tests, failed 0, skipped 0
- iPhone 16 Simulator Debug build: succeeded
- generic iPhone Simulator Debug build: succeeded
- generic iPhone Simulator Release build: succeeded
- `Scripts/check-iphone-functional-gate.sh`: passed
- `Scripts/check-swiftdata-boundary.sh`: passed
- `plutil -lint Moru/Info.plist`: passed
- `git diff --check`: passed
- Domain/Data/schema/migration/Repository/DependencyContainer/SessionStore 변경: 0건
- Xcode project 변경: 0건
