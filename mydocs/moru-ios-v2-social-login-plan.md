# MORU iOS 선택형 소셜 로그인 고정 실행 계획

- 원본 고정 계획: `/Users/minhyeok/Downloads/PLAN (5).md`
- 실행 기준: P5 `feat/#92-account-lifecycle`
- 기준 SHA: `e4ea5b1fd3e8397b1897ae6adf89958f59cd6266`
- 정책: 모든 PR은 Draft + OPEN으로 동결하고 일괄 검토 전 merge하지 않는다.

## 고정 결정

- 로그인 공급자는 Apple, Google, Kakao 3종이다.
- 첫 설치에서 로그인을 제안하지만 `로그인 없이 시작하기`를 제공한다.
- 기존 로컬 사용자는 로그인 화면을 거치지 않는다.
- SwiftData와 Local Repository가 화면의 Source of Truth다.
- 로그인 성공 여부와 무관하게 서버 데이터로 로컬 루틴과 기록을 자동 교체하지 않는다.
- 공급자별 계정은 서로 다른 MORU 계정이며 이메일로 자동 병합하지 않는다.
- 공식 브랜드 버튼을 사용하며 Kakao 원형 아이콘만으로 로그인하지 않는다.
- client secret, Apple `.p8`, Kakao admin key를 앱이나 저장소에 넣지 않는다.

## Stacked PR

| ID | Branch | Commit·PR 제목 |
| --- | --- | --- |
| L0 | `feat/#<issue>-social-login-foundation` | `[Feat] 소셜 로그인 공통 기반 보강` |
| L1 | `feat/#<issue>-apple-login-readiness` | `[Feat] Apple 로그인 출시 흐름 완성` |
| L2 | `feat/#<issue>-google-login` | `[Feat] Google 로그인 구현` |
| L3 | `feat/#<issue>-kakao-login` | `[Feat] Kakao 로그인 구현` |
| L4 | `feat/#<issue>-optional-login-entry` | `[Feat] 선택형 소셜 로그인 진입 화면 구현` |

L0는 P5의 정확한 SHA에서 시작한다. L1부터는 직전 로그인 PR branch를 base로 하는
단일 stacked chain으로 진행한다. 기존 P6~P8 branch는 수정하지 않는다.

## L0 — 공통 인증 기반

- Apple 전용 서비스를 `SocialLoginCoordinator`와 공급자별 authorization adapter
  구조로 일반화한다.
- `AccountCredentials`와 `SignedInAccount`에 로그인 공급자를 저장한다.
- provider 필드가 없는 기존 Keychain payload는 기존 Apple-only 세션으로 안전하게
  복원한다.
- `AppCapabilities`를 계정 UI, 계정 복원, 모든 서버 호출의 master kill switch로
  연결한다.
- Google/Kakao callback을 받을 루트 `AuthCallbackRouter`를 둔다.
- Google/Kakao 공개 식별자용 build configuration을 준비한다.
- 401 재발급 뒤 logout 재시도는 회전된 refresh token으로 target을 다시 만든다.
- token, authorization code, nonce가 로그·description·snapshot에 노출되지 않는다.
- SwiftData schema·migration, Local Repository, routine Domain 계약을 변경하지 않는다.

## L1 — Apple

- `AuthenticationServices` 흐름을 공통 coordinator에 연결한다.
- 암호학적 nonce, Apple user identifier, credential state, revoked 알림을 처리한다.
- 서버에 identity token, authorization code, raw nonce를 전달한다.
- 이름·이메일 scope를 요청하지 않는다.
- 회원 탈퇴 때 서버의 Apple token revoke 완료를 검증한다.

## L2 — Google

- 공식 GoogleSignIn-iOS 9.1.x를 고정한다.
- iOS/Web client ID와 reversed URL scheme을 구성한다.
- 추가 Google API scope 없이 로그인하고 갱신된 ID token만 서버에 전달한다.
- 취소는 오류로 표시하지 않고 로그아웃 때 로컬 SDK 세션도 정리한다.

## L3 — Kakao

- Kakao iOS SDK 2.28.x를 고정한다.
- Native app key, URL scheme, Kakao Talk 조회 scheme을 구성한다.
- Talk 설치 시 Talk 로그인, 미설치 시 Kakao Account 로그인을 사용한다.
- 사용자 취소 때 자동 fallback하지 않는다.
- 일반 로그아웃과 회원 탈퇴 unlink 흐름을 구분한다.

## L4 — 선택형 진입과 통합

- Splash는 bootstrap 로딩 전용으로 유지하고 별도 AccountEntryView를 둔다.
- LocalProfile이 있으면 계정 상태와 무관하게 Main으로 진입한다.
- LocalProfile이 없고 계정 복원 중이면 Splash를 유지한다.
- LocalProfile이 없고 미로그인이면 선택형 로그인 화면을 표시한다.
- 로그인 성공 또는 건너뛰기 뒤 기존 로컬 온보딩을 진행한다.
- 로그아웃·토큰 만료·탈퇴 뒤에도 로컬 프로필과 루틴이 있으면 Main을 유지한다.
- 공식 provider 버튼, 건너뛰기, local-first 안내, 정책 링크를 제공한다.

## 공통 검증

- 관련 테스트와 전체 XCTest, failed/skipped 0
- iPhone 16 Simulator Debug
- generic iPhone Debug/Release
- `bash Scripts/check-iphone-functional-gate.sh`
- `bash Scripts/check-swiftdata-boundary.sh`
- Info.plist와 entitlement `plutil`
- `git diff --check`
- SwiftData schema·migration·Local Repository 변경 0
- 자체 코드 리뷰
- 실제 iPhone 미검증 항목을 통과로 기록하지 않는다.

## 실행 전 외부 입력

- Google Cloud iOS/Web OAuth client ID와 backend audience
- Kakao Developers Native app key와 bundle ID/Login 활성화
- Apple provisioning과 서버 token 검증/revoke 준비
- 공개 개인정보처리방침·이용약관·지원 URL
- 정확한 로그인 Figma node와 공식 provider asset
