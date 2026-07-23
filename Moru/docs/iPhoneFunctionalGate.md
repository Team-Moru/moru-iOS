# MORU iOS v1 iPhone 기능 게이트

## 지원 범위

- 최소 OS: iOS 26
- 기기: iPhone
- 방향: 세로(portrait)
- 언어와 시간대: 한국어, Asia/Seoul
- 화면 스타일: Light
- 후속 범위: iPad, 가로 화면, Dark 디자인

앱 타깃과 테스트 타깃은 iPhone device family만 지원한다.
앱의 Debug와 Release 구성 및 Info.plist에는
`UIInterfaceOrientationPortrait`만 선언한다.

## 알람 진입 계약

- 정상 AlarmKit의 `루틴 시작` 액션은 AlarmRing을 거치지 않고
  해당 루틴의 `.scheduled` RoutinePlayer로 바로 진입한다.
- 현재 alert stop 실패와 UserNotifications fallback 탭에서만 AlarmRing을 표시한다.
- UserNotifications fallback은 AlarmKit과 같은 전달 보장을 제공하지 않는다.
- 알람은 시스템 기본음 한 종류만 사용한다.
  사운드 카탈로그, 번들 알람음, 선택 UI, 볼륨 슬라이더는
  v1 범위가 아니다.

## 음성 계약

- RoutinePlayer 안내는 네 종류의 번들 MP3만 사용한다.
- 직접 작성 step 또는 매핑이 없는 cue는 무음으로 정상 진행한다.
- 로컬 TTS fallback, 키보드 입력, 별도 확인 버튼은 추가하지 않는다.
- STT 침묵 자동 종료 기준은 3초다.
  마지막 transcript를 자동 완료 판정에 전달한다.
- 음성 인식 권한 거부 시에는 설정 이동과
  해당 단계 건너뛰기만 제공한다.
- `intro 완료 → STT 시작`,
  `STT 완료 → done 완료 → 다음 step` 순서를 유지한다.

## 자동 검증

PR에서 다음 검증을 모두 수행한다.

1. `bash Scripts/check-iphone-functional-gate.sh`
2. 관련 테스트와 전체 XCTest
3. iPhone Simulator Debug build
4. generic iPhone Debug/Release build
5. `bash Scripts/check-swiftdata-boundary.sh`
6. `git diff --check`
7. SwiftData schema와 migration 변경 없음 확인

`check-iphone-functional-gate.sh`는 Xcode project와 Info.plist의 iPhone-only/portrait 설정,
Light 고정, README와 이 문서의 핵심 계약을 CI에서 검사한다.

## 실제 iPhone 최종 E2E

```text
첫 설치 → 온보딩 → 첫 루틴/알람 저장
→ 앱 종료/재실행 → 데이터와 예약 유지
→ locked/killed 상태의 실제 AlarmKit → RoutinePlayer 직접 진입
→ fallback 알림 → AlarmRing → 시작 또는 다시 알림
→ MP3 intro → STT → done MP3 → 다음 step
→ RoutineRun 저장 → Home/History 반영
→ 추천/직접 루틴 추가
→ 모든 루틴 삭제 후 Main empty state 유지
→ 수정/비활성/삭제/reset → 예전 알람 미발생
```

스피커, Bluetooth, 전화/Siri interruption과 WeatherKit 실제 권한도 확인한다.
실제 iPhone에서 수행하지 않은 항목은 통과로 기록하지 않으며,
남은 출시 차단 위험과 후속 QA로 명시한다.
