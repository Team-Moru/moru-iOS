# MORU iOS v2 Social Login 실행 Context

- 마지막 갱신: 2026-07-27
- 상태: `L3_OPEN_DRAFT`
- 고정 계획: `mydocs/moru-ios-v2-social-login-plan.md`
- 원본 계획: `/Users/minhyeok/Downloads/PLAN (5).md`
- v2 context:
  `/Users/minhyeok/Developer/projects/moru-iOS/mydocs/moru-ios-v2-local-first-server-expansion-context.md`

## 실행 기준

- 저장소: `Team-Moru/moru-iOS`
- L0 base branch: `feat/#92-account-lifecycle`
- L0 base SHA: `e4ea5b1fd3e8397b1897ae6adf89958f59cd6266`
- L0 Worktree: `/private/tmp/moru-ios-l0.4wP3Fn`
- L1 Worktree: `/private/tmp/moru-ios-l1.lOeClO`
- 원본 dirty worktree는 읽기만 하고 변경하지 않는다.
- SwiftData schema·migration, Local Repository, routine Domain 계약은 변경하지 않는다.
- 로그인은 선택 기능이며 SwiftData/Local Repository가 계속 Source of Truth다.
- 모든 로그인 PR은 Draft + OPEN으로 동결하며 merge하지 않는다.

## L0 Ledger

- Issue: https://github.com/Team-Moru/moru-iOS/issues/101
- PR: https://github.com/Team-Moru/moru-iOS/pull/102 (`OPEN`, `DRAFT`)
- Branch: `feat/#101-social-login-foundation`
- Base SHA: `e4ea5b1fd3e8397b1897ae6adf89958f59cd6266`
- 구현 Head SHA: `184737bae6c02df6fe5cf07064b0a385a70ff98b`
- 최종 PR Head: 이 ledger 문서 commit(정확한 SHA는 PR #102 기준)
- Merge SHA: 없음
- 구현 기능: L0 로컬 구현 완료
- 주요 계약 변경:
  - provider 공통 authorization/coordinator와 Apple adapter
  - credential/session provider 저장 및 legacy Apple decoding
  - 계정 UI·복원·서버 요청 master kill switch
  - Google/Kakao callback root와 공개 build configuration
  - 401 이후 회전된 refresh token을 사용하는 logout retry target
- SwiftData/schema 변경: 없음(고정)
- 테스트:
  - 관련 XCTest 73/73 성공, failed/skipped 0
  - 전체 XCTest 359/359 성공, failed/skipped 0
- 빌드:
  - iPhone 16 Simulator Debug 성공
  - generic iPhone Debug 성공
  - generic iPhone Release 성공
- 정적 검증:
  - iPhone functional gate 성공
  - SwiftData boundary gate 성공
  - Info.plist/entitlement `plutil` 성공
  - `git diff --check` 성공
  - client secret·admin key·private key·`.p8` 저장소 노출 없음
- 실제 iPhone: 미검증
- 리뷰:
  - 로컬 자체 리뷰 완료
  - GitHub inline review thread 0개, review decision 없음
  - CodeRabbit은 Draft 정책에 따라 review를 건너뜀
- CI:
  - iPhone portrait functional gate 성공
  - Foundation SwiftData boundary 성공
  - standalone `swiftdata-boundary` 성공
  - CodeRabbit status 성공(Draft review skipped)
- 남은 위험:
  - 실제 Google/Kakao SDK callback handler와 URL scheme은 L2/L3에서 연결 필요
  - 실제 iPhone과 실제 provider console/backend 연동은 아직 미검증
- L1 입력:
  - `SocialLoginCoordinator`와 `AppleAuthorizationAdapter`
  - provider가 보존되는 `AccountCredentials`/`SignedInAccount`
  - `AuthCallbackRouter`와 `SocialLoginPublicConfiguration`
  - `AppCapabilities` master kill switch
  - 회전 토큰을 반환하는 `AccessTokenRefreshResult`
  - Draft PR 생성·CI 확인·OPEN 동결 후 L1을 시작할 것

## L1 Ledger

- Issue: https://github.com/Team-Moru/moru-iOS/issues/103
- PR: https://github.com/Team-Moru/moru-iOS/pull/104 (`OPEN`, `DRAFT`)
- Branch: `feat/#103-apple-login-readiness`
- Base branch: `feat/#101-social-login-foundation`
- Base SHA: `88b5ae3921f6556925c1075897e64744869da537`
- 구현 Head SHA: `bc7d113271f392327ae9bdfd14b824ec6ca855f5`
- 최종 PR Head: 이 ledger 문서 commit(정확한 SHA는 PR #104 기준)
- Merge SHA: 없음
- 구현 기능:
  - `SecRandomCopyBytes` 32자 raw nonce와 SHA-256 Apple request challenge
  - identity token·authorization code·raw nonce·Apple user identifier의 요청 단위
    binding과 공통 `SocialLoginCoordinator` 연결
  - 이름·이메일 scope 미요청
  - Apple user identifier의 Keychain/session 저장과 token rotation 보존
  - credential state 확인과 `credentialRevokedNotification` 재확인
  - revoked/notFound/transferred 시 local account session 무효화
- 주요 계약 변경:
  - Apple authorization은 raw nonce와 user identifier가 없으면 server 호출 전에 거부
  - `AccountCredentials`와 `SignedInAccount`에 optional provider user identifier 추가
  - L0 이전 credential은 provider를 Apple로 복원하고 user identifier는 `nil`로
    하위 호환
  - token, authorization code, raw nonce, provider user identifier description redaction
- 서버 계약 확인(2026-07-27):
  - 실제 `/v3/api-docs`의 `SocialLoginRequest`는 `token`,
    `authorizationCode`만 지원
  - raw nonce와 Apple user identifier는 OpenAPI 미지원이므로 request body에 추정
    추가하지 않음
  - `DELETE /auth/withdrawal` 성공 응답은 MORU 회원 탈퇴 message만 제공하며 Apple
    token revoke 완료 증거가 없음
  - 상세 blocker: `Moru/docs/AppleLoginReadiness.md`
- SwiftData/schema·migration 변경: 없음(고정)
- Local Repository·routine Domain 계약 변경: 없음(고정)
- 테스트:
  - 관련 XCTest 68/68 성공, failed/skipped 0
  - 전체 XCTest 363/363 성공, failed/skipped 0
- 빌드:
  - MORU Release iPhone 16 Simulator Debug 성공
  - generic iPhone Debug 성공
  - generic iPhone Release 성공
- 정적 검증:
  - iPhone functional gate 성공
  - SwiftData boundary gate 성공
  - Info.plist/entitlement `plutil` 성공
  - `git diff --check` 성공
  - client secret·admin key·private key·`.p8` 저장소 노출 없음
- 실제 iPhone: 미검증
  - Apple 로그인 성공·취소·재실행
  - credential state와 revoked notification
  - Keychain session 복원과 회원 탈퇴
- 리뷰:
  - 로컬 자체 리뷰 완료
  - 구현 Head 기준 GitHub inline review thread 0개, review decision 없음
  - CodeRabbit 성공(Draft review 정책)
- CI(구현 Head 기준, ledger 작성 시점):
  - Foundation Checks 진행 중
  - SwiftData Boundary 진행 중
  - Discord PR notification 성공
- 남은 위험·release blocker:
  - 서버 raw nonce 검증 계약과 실패 응답이 없어 nonce E2E 미완성
  - 회원 탈퇴 응답으로 Apple provider token revoke 완료를 검증할 수 없음
  - L0 이전 Apple credential은 user identifier가 없어 다음 재인증 전 credential
    state 자동 검증 불가
  - Apple Team provisioning과 실제 서버·실제 iPhone E2E 미검증
- L2 입력:
  - provider payload를 보존하는 `SocialAuthorization`과 공통 coordinator
  - provider user identifier를 하위 호환 저장하는 credential/session
  - provider별 adapter 경계와 root `AuthCallbackRouter`
  - `AppCapabilities` account/server master kill switch
  - Apple credential monitor는 Apple session만 처리하므로 Google session과 분리
  - L1 Draft PR #104의 CI 확인·OPEN 동결 후 GoogleSignIn-iOS 9.1.x를 고정할 것

## L2 Ledger

- Issue: https://github.com/Team-Moru/moru-iOS/issues/105
- PR: https://github.com/Team-Moru/moru-iOS/pull/106 (`OPEN`, `DRAFT`)
- Branch: `feat/#105-google-login`
- Base branch: `feat/#103-apple-login-readiness`
- Base SHA: `1bd92a1fcb6fcbe0e0dddb8503fe9ec3743ffa64`
- Worktree: `/private/tmp/moru-ios-l2.sItVax`
- 구현 Head SHA: `74d1a37133d9b271638e8005b24441757d173de8`
- 최종 PR Head: 이 ledger 문서 commit(정확한 SHA는 PR #106 기준)
- Merge SHA: 없음
- 구현 기능:
  - GoogleSignIn-iOS `9.1.0..<9.2.0` SPM 요구사항과 `9.1.0` resolved pin
  - 앱 target에 최소 `GoogleSignIn`, `GoogleSignInSwift` product만 직접 연결
  - iOS client ID·server client ID·reversed URL scheme의 공개 build configuration과
    형식·상호 일치 gate
  - 공식 Google SwiftUI 버튼과 앱 루트 `onOpenURL` →
    `AuthCallbackRouter` → Google SDK callback 연결
  - 추가 Google API scope 없이 로그인한 뒤 `refreshTokensIfNeeded()`로 갱신한
    ID token만 MORU `POST /auth/login/google`의 `token`으로 전달
  - `GIDSignInErrorCodeCanceled`는 사용자 오류·MORU 서버 요청 없이 취소 처리
  - Google 계정의 MORU 로그아웃·회원 탈퇴 때 Google SDK local session sign-out
- 주요 계약 변경:
  - `AccountLifecycleCredentials`가 provider를 보존하고 stored/session provider가
    일치할 때만 account lifecycle credential로 사용
  - account lifecycle에 provider SDK session sign-out 경계를 추가
  - stored credential을 읽지 못해도 현재 signed-in provider가 Google이면 SDK
    local session을 정리
  - Google access token·refresh token·profile·email·authorization code는 MORU
    서버 요청에 포함하지 않음
  - Google 로그인 성공 여부와 무관하게 로컬 프로필·루틴·기록 교체 없음
- 공개 configuration blocker:
  - 실제 Google Cloud iOS/Web OAuth client ID와 reversed URL scheme을 제공받지 못함
  - Debug/Release에는 실제 값으로 오인되지 않는 명시적 placeholder를 두고 로그인과
    callback을 차단
  - MORU backend가 검증할 Web/server client ID audience 미확정
  - 상세 설정·검증 대기 항목: `Moru/docs/GoogleLoginReadiness.md`
- SwiftData/schema·migration 변경: 없음(고정)
- Local Repository·routine Domain 계약 변경: 없음(고정)
- 테스트:
  - 관련 XCTest 25/25 성공, failed/skipped 0
  - 전체 XCTest 371/371 성공, failed/skipped 0
- 빌드:
  - MORU Release iPhone 16 Simulator Debug 성공
  - generic iPhone Debug 성공
  - generic iPhone Release 성공
- 정적 검증:
  - iPhone functional gate 성공
  - SwiftData boundary gate 성공
  - source Info.plist·entitlement와 Debug/Release built Info.plist `plutil` 성공
  - `git diff --check` 성공
  - Google client secret·private key·서비스 계정 credential 저장소 추가 없음
- 실제 iPhone: 미검증
  - 공식 Google 버튼 로그인 성공·취소와 Google app/Safari 전환
  - reversed URL callback 복귀
  - 갱신된 ID token의 실제 backend audience 검증
  - 로그아웃·회원 탈퇴 뒤 SDK session 정리와 재로그인
  - 앱 재실행 뒤 MORU Keychain session 복원
- 리뷰:
  - 로컬 자체 리뷰 완료
  - GitHub review·inline thread와 CI는 최종 ledger head push 후 확인
- 남은 위험·release blocker:
  - 실제 OAuth client ID·consent screen·테스트 계정·backend audience가 없어
    Google E2E를 수행할 수 없음
  - 실제 Google Console 설정·실제 MORU backend·실제 iPhone 동작 미검증
  - placeholder build는 Google 로그인을 의도적으로 제공하지 않음
- L3 입력:
  - provider payload를 보존하는 `SocialAuthorization`과 공통 coordinator
  - root `AuthCallbackRouter`의 Kakao handler 등록 경계
  - 공개 식별자를 읽는 `SocialLoginPublicConfiguration`
  - provider를 보존하는 account lifecycle credential과 SDK session sign-out 경계
  - L3에서는 Google·Kakao local sign-out을 함께 보존하는 provider router/composite를
    구성할 것
  - Google session과 Apple credential monitor는 각 provider에만 반응
  - AppCapabilities account/server master kill switch와 local-first Source of Truth
  - L2 Draft PR #106의 CI 확인·OPEN 동결 후 Kakao iOS SDK 2.28.x를 고정할 것

## L3 Ledger

- Issue: https://github.com/Team-Moru/moru-iOS/issues/107
- PR: https://github.com/Team-Moru/moru-iOS/pull/108 (`OPEN`, `DRAFT`)
- Branch: `feat/#107-kakao-login`
- Base branch: `feat/#105-google-login`
- Base SHA: `86ff16379b52230f479aa099d36bc2b2fc084a8b`
- Worktree: `/private/tmp/moru-ios-l3.PvWgag`
- 구현 Head SHA: `935c383b913bb8027b1418c2df11714934347045`
- 최종 PR Head: 이 ledger 문서 commit(정확한 SHA는 PR #108 기준)
- Merge SHA: 없음
- 구현 기능:
  - Kakao iOS SDK 원격 SPM `2.28.0` pin과 앱 target의 최소
    `KakaoSDKCommon`, `KakaoSDKAuth`, `KakaoSDKUser` product 직접 연결
  - 32자리 16진수 Native app key와 정확한 `kakao{NativeAppKey}` callback scheme을
    함께 검증하는 공개 build configuration gate
  - Kakao Talk 조회용 `kakaokompassauth` scheme과 앱 루트 `onOpenURL` →
    `AuthCallbackRouter` → Kakao SDK callback 연결
  - 공식 Kakao 한국어 medium-wide PNG 로그인 버튼
  - Talk 설치 시 Talk 로그인만, 미설치 시 Kakao Account 로그인만 수행하며
    사용자 취소·실패 뒤 자동 fallback 없음
  - Kakao access token만 MORU `POST /auth/login/kakao`의 `token`으로 전달
  - MORU 로그아웃 때 Kakao SDK `UserApi.logout`, MORU 회원 탈퇴 서버 성공 뒤
    Kakao SDK `UserApi.unlink` 수행
  - Google·Kakao provider SDK local session 정리를 함께 보존하는 composite
- 주요 계약 변경:
  - configuration gate를 통과한 경우에만 Kakao SDK 초기화·로그인·callback 처리
  - Kakao refresh token·ID token·profile·email·authorization code는 MORU 서버
    요청에 포함하지 않음
  - Talk 설치 여부가 로그인 adapter를 결정하며 취소·오류 때 다른 adapter로 전환하지
    않음
  - 일반 로그아웃은 Kakao session logout, 회원 탈퇴는 MORU 서버 성공 뒤 unlink
  - provider sign-out composite가 Google·Kakao 정리 경계를 모두 보존
  - Kakao 로그인 성공 여부와 무관하게 로컬 프로필·루틴·기록 교체 없음
- SDK pin:
  - 원격 URL: `https://github.com/kakao/kakao-ios-sdk`
  - resolved version/revision: `2.28.0` /
    `2a68ca01e2d7900a1559b31d0d59843837f130f2`
  - 직접 연결 product: `KakaoSDKCommon`, `KakaoSDKAuth`, `KakaoSDKUser`
- 공개 configuration blocker:
  - 실제 Kakao Developers Native app key를 제공받지 못함
  - Kakao Developers에 bundle ID `com.teammoru.Moru` 등록 필요
  - Kakao Login 활성화와 필요한 동의 항목 설정 필요
  - Debug/Release 환경별 Native app key와 callback scheme 운영값 확정 필요
  - MORU backend의 실제 Kakao access token 검증 E2E 필요
  - placeholder configuration은 실제 값으로 오인되지 않으며 로그인과 callback을 차단
  - 상세 설정·검증 대기 항목: `Moru/docs/KakaoLoginReadiness.md`
- SwiftData/schema·migration 변경: 없음(고정)
- Local Repository·routine Domain 계약 변경: 없음(고정)
- 테스트:
  - 관련 XCTest 46/46 성공, failed/skipped 0
  - 전체 XCTest 380/380 성공, failed/skipped 0
- 빌드:
  - 원격 Kakao SPM package resolution 성공
  - iPhone 16 Simulator Debug 성공
  - generic iPhone Debug 성공
  - generic iPhone Release 성공
- 정적 검증:
  - iPhone functional gate 성공
  - SwiftData boundary gate 성공
  - source Info.plist·entitlement와 Debug/Release built Info.plist `plutil` 성공
  - `git diff --check` 성공
  - Kakao admin key·client secret·private key·실제 Native app key 저장소 추가 없음
- 실제 iPhone: 미검증
  - Kakao Talk 설치 상태의 로그인·취소·callback 복귀
  - Kakao Talk 미설치 상태의 Kakao Account 로그인·취소
  - 사용자 취소·실패 뒤 다른 로그인 방식으로 fallback하지 않는지 확인
  - Kakao access token만 사용하는 실제 MORU backend E2E
  - 로그아웃·회원 탈퇴 unlink·재로그인
  - 앱 재실행 뒤 MORU Keychain session 복원
- 리뷰:
  - 로컬 자체 리뷰 완료
  - GitHub review·inline thread와 CI는 최종 ledger head push 후 확인
- CI(ledger 작성 시점):
  - 최종 ledger head push 후 확인
- 남은 위험·release blocker:
  - 실제 Native app key·Kakao Developers bundle/Login/consent 설정이 없어 Kakao
    로그인을 활성화할 수 없음
  - 실제 MORU backend의 Kakao access token 검증과 실패 응답 계약 미검증
  - 실제 Kakao Talk·Kakao Account·callback·logout·unlink의 실제 iPhone 동작 미검증
  - placeholder build는 Kakao 로그인을 의도적으로 제공하지 않음
- L4 입력:
  - Apple·Google·Kakao 3개 provider를 보존하는 `SocialLoginCoordinator`와 공식
    provider 버튼
  - Google·Kakao callback을 처리하는 root `AuthCallbackRouter`
  - provider별 configuration gate와 `AppCapabilities` account/server master kill switch
  - 로그아웃·탈퇴 뒤 provider SDK session까지 정리하는 account lifecycle composite
  - SwiftData/Local Repository가 Source of Truth인 local-first 계약
  - Splash는 bootstrap 로딩 전용으로 유지하고 별도 `AccountEntryView`를 둘 것
  - LocalProfile이 있으면 계정 상태와 무관하게 Main으로 진입할 것
  - LocalProfile이 없고 계정 복원 중이면 Splash, 미로그인이면 선택형 로그인 화면을
    표시할 것
  - 로그인 성공 또는 건너뛰기 뒤 기존 로컬 온보딩을 진행할 것
  - 로그아웃·토큰 만료·탈퇴 뒤에도 로컬 프로필과 루틴이 있으면 Main을 유지할 것
  - 공식 provider 버튼, `로그인 없이 시작하기`, local-first 안내, 정책 링크를 제공할 것
  - L3 Draft PR #108의 CI 확인·OPEN 동결 후 선택형 로그인 진입 화면을 구현할 것

## L0 고정 범위

- SocialLoginCoordinator와 provider authorization adapter
- credential/session provider 저장과 legacy Keychain decoding
- AppCapabilities master kill switch
- Google/Kakao callback root와 공개 식별자 build configuration
- 401 reissue 뒤 logout refresh token retarget
- secret·token·authorization payload redaction

## 금지 범위

- Apple nonce, credential state, revoke 알림의 출시 완성
- Google/Kakao SDK 추가와 실제 로그인
- 선택형 로그인 진입 화면
- SwiftData와 routine Domain/Repository 계약 변경
- 기존 P6~P8 branch 변경
- merge
