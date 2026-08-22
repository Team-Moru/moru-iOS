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

- 로그인 계정의 서버 binding과 검증된 로컬 캐시가 준비된 경우
  RoutinePlayer의 `intro`는 루틴별 원격 TTS를, `done`·`remind`는 선택 음성별
  공통 원격 TTS를 우선 재생한다. 서버 `intro` 캐시가 없으면 첫 재생 전에 제한된
  foreground 준비 시간 동안 생성 상태 확인과 다운로드를 기다린다.
- 서버 공통 `done`·`remind`가 PENDING/FAILED이거나 캐시·재생에 실패하면
  로그인 세션은 무음으로 진행한다. 다른 번들 목소리로 fallback하지 않는다.
- 네 종류의 번들 MP3는 로그인하지 않은 로컬 루틴의 `intro`·`done`·`remind`와
  루틴별 원격 TTS가 없는 로컬 fallback에만 사용한다.
- 실제 재생은 원격 URL을 스트리밍하지 않고 검증된 로컬 파일만 사용한다.
  `done`·`remind`는 cue 시점에 네트워크 완료를 기다리지 않는다.
- 타이머 진행 중간의 `remind`는 재생하지 않는다. 마지막 5초 system countdown과
  자동 다음 단계 전환은 유지한다.
- 원격·번들 매핑이 모두 없는 cue는 무음으로 정상 진행한다.
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
→ 캐시된 원격 TTS intro 또는 로컬 번들 MP3 fallback
→ STT → 캐시된 선택 음성 done 또는 로그인 상태에 맞는 fail-open → 다음 step
→ RoutineRun 저장 → Home/History 반영
→ 추천/직접 루틴 추가
→ 모든 루틴 삭제 후 Main empty state 유지
→ 수정/비활성/삭제/reset → 예전 알람 미발생
```

온라인 warmup, 오프라인 fallback, 만료된 presigned URL, 계정 전환과 함께
스피커, Bluetooth, 전화/Siri interruption과 WeatherKit 실제 권한도 확인한다.
실제 iPhone에서 수행하지 않은 항목은 통과로 기록하지 않으며,
남은 출시 차단 위험과 후속 QA로 명시한다.

### 서버 음성 백그라운드 전송 수동 검증

시뮬레이터의 background URLSession 스케줄링은 실제 iOS와 같다고 볼 수 없으므로
다음 항목은 TestFlight를 설치한 실제 iPhone에서 별도로 확인한다.

- 프로필에서 서버 음성을 선택한 직후 앱을 백그라운드로 보내고 화면을 잠근다.
  잠금 중에도 준비된 `intro`·`done`·`remind` 다운로드가 이어지고, 다시 앱을 열면
  준비 완료 상태와 로컬 캐시 재생이 유지되는지 확인한다.
- 다운로드 도중 앱 프로세스를 종료한 다음 명시적으로 다시 실행한다. 남아 있던
  작업이 계정·루틴·음성 선택 버전 기준으로 한 번만 재개되는지 확인한다.
  사용자가 앱을 강제 종료한 동안의 완료는 보장하지 않으며, 다음 실행 시 재개가
  이 검증의 합격 기준이다.
- 네트워크를 끈 상태에서 실제 알람으로 RoutinePlayer에 진입한다. 서버 음성 준비가
  끝나지 않았거나 캐시가 없으면 제한된 foreground 준비가 종료된 뒤 오류 화면이나
  번들 음성 대체 없이 무음으로 루틴이 진행되는지 확인한다.
