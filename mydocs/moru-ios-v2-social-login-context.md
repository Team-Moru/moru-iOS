# MORU iOS v2 Social Login 실행 Context

- 마지막 갱신: 2026-07-27
- 상태: `L5_OPEN_DRAFT`
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

## L4 Ledger

- Issue: https://github.com/Team-Moru/moru-iOS/issues/109
- PR: https://github.com/Team-Moru/moru-iOS/pull/110 (`OPEN`, `DRAFT`)
- Branch: `feat/#109-optional-login-entry`
- Base branch: `feat/#107-kakao-login`
- Base SHA: `36153d844047d8ed6f8d8990ab861237862116ae`
- Worktree: `/private/tmp/moru-ios-l4.Ysq7LY`
- 구현 Head SHA: `72782b1706ced97313c9854e809325e718eaec40`
- 최종 PR Head: 이 ledger 문서 commit(정확한 SHA는 PR #110 기준)
- Merge SHA: 없음
- 구현 기능:
  - bootstrap·계정 복원 로딩 전용 Splash와 별도 `AccountEntryView`
  - LocalProfile이 있으면 signed-out·restoring·signed-in·복원 실패와 관계없이 Main
  - LocalProfile이 없으면 restoring은 Splash, signed-out·복원 실패는 선택형 진입,
    signed-in·로그인 성공·건너뛰기는 기존 로컬 온보딩
  - Apple·Google 공식 SDK 버튼과 저장소의 공식 Kakao 한국어 medium-wide asset
  - `로그인 없이 시작하기`, local-first·타 기기 데이터 자동 복원/교체 없음 안내,
    개인정보처리방침·이용약관 링크
  - loading·cancel·offline·401·5xx·Keychain·invalid stored credential 상태와
    중복 요청 방지
- 주요 계약 변경:
  - 앱 root routing을 테스트 가능한 `AppRootDestination`으로 명시하고 LocalProfile을
    계정 세션보다 우선
  - bootstrap이 ready graph를 공개하기 전에 account state를 restoring으로 바꿔
    미로그인 화면의 일시 노출을 방지
  - provider credential/provisioning gate와 공개 정책 HTTPS URL 두 개가 모두
    준비된 경우에만 provider 인증을 활성화
  - provider 인증이 비활성화되어도 guest 로컬 온보딩은 항상 유지
  - 로그인 성공 여부와 무관하게 서버 데이터로 로컬 프로필·루틴·기록을 교체하지 않음
  - SwiftData schema·migration, Local Repository, routine Domain 계약 변경 없음
- 공개 configuration safe gate:
  - Debug/Release `MORU_APPLE_SIGN_IN_ENABLED=NO`
  - Google/Kakao placeholder configuration은 기존 provider gate로 로그인 차단
  - 공개 개인정보처리방침·이용약관 운영 URL이 없어 placeholder를 링크로 인정하지
    않고 모든 provider 인증을 차단
  - client secret·Apple `.p8`·Kakao admin key·실제 credential 저장소 추가 없음
  - 상세 준비 항목: `Moru/docs/OptionalLoginEntryReadiness.md`
- 테스트:
  - 관련 signed XCTest 15/15 성공, failed/skipped/expected failure 0
    (`/private/tmp/moru-ios-l4-related4.xcresult`)
  - 최종 전체 signed XCTest 394/394 성공, failed/skipped/expected failure 0
    (`/private/tmp/moru-ios-l4-full-final.xcresult`)
- 빌드:
  - MORU Release iPhone 16, iOS 26.5 Simulator Debug 성공
  - generic iPhone Debug 성공
  - generic iPhone Release 성공
- 정적 검증:
  - iPhone functional gate 성공
  - SwiftData boundary gate 성공
  - source Info.plist·entitlement와 Debug/Release built Info.plist `plutil` 성공
  - Debug/Release built Info.plist의 Apple gate `NO`, policy URL placeholder 확인
  - `git diff --check` 성공
- visual·accessibility:
  - idle·loading·cancel·offline·401·5xx·Keychain·긴 한국어 8상태를 Medium·AX3에서
    각 2회 렌더링해 32개 PNG가 byte-identical임을 확인
  - capture: `/private/tmp/moru-optional-login-after`
  - idle Medium·idle AX3·긴 한국어 AX3 대표 산출물 수동 확인
  - 고유 accessibility identifier와 title → local-first 안내 → 상태 → Apple →
    Google → Kakao → guest → 정책 링크 VoiceOver 순서 계약 테스트 성공
  - 이전에 같은 화면이 없고 정확한 Figma node가 없어 동환경 before capture와
    pixel-match 승인 결과는 없음
- 실제 iPhone: 미검증
  - Apple·Google·Kakao 성공·취소·callback 복귀
  - 비행기 모드·네트워크 단절과 실제 backend 401/5xx
  - Keychain 읽기·저장 실패와 앱 재실행 session 복원
  - 로그아웃·토큰 만료·회원 탈퇴 뒤 기존 LocalProfile/Main 유지
  - Medium·AX3·긴 한국어와 공식 버튼의 실제 VoiceOver 순서·레이블
- Figma·provider·policy release blocker:
  - 정확한 로그인 Figma node ID·계측 asset이 없어 기존 MORU token 기반 구조만
    구현했으며 exact pixel match를 주장하지 않음
  - Google Cloud iOS/Web OAuth client ID·reversed scheme·backend audience 필요
  - Kakao Native app key·bundle/Login/consent 설정과 backend token 검증 필요
  - Apple Team provisioning·server raw nonce 검증·provider token revoke 증거 필요
  - 공개 개인정보처리방침·이용약관·지원 URL 필요
  - 실제 provider console·MORU backend·실제 iPhone E2E 필요
- 리뷰:
  - 로컬 자체 리뷰 완료
  - GitHub review·inline thread와 CI는 최종 ledger head push 후 확인
- CI(ledger 작성 시점):
  - 최종 ledger head push 후 확인
- 전체 stack 최종 검토 입력:
  - L0 #102 → L1 #104 → L2 #106 → L3 #108 → L4 #110은 모두 Draft + OPEN
  - 각 PR의 base branch·구현 Head·ledger·CI와 secret 비노출을 순서대로 확인
  - Apple raw nonce/revoke, Google audience, Kakao token 검증과 provider별 실제
    console 설정을 하나의 release readiness checklist로 검토
  - LocalProfile 우선 Main, local-first Source of Truth, 서버 데이터 자동 교체 없음,
    guest 경로, account/server kill switch를 stack 공통 회귀 계약으로 확인
  - 실제 공개 정책 URL과 provider credential/provisioning이 준비되기 전에는
    provider gate를 활성화하지 않음
  - 실제 iPhone 3-provider·callback·Keychain·logout/withdrawal·VoiceOver E2E와
    정확한 Figma node visual 승인이 끝나기 전 merge하지 않음
  - `DO NOT MERGE — 소셜 로그인 stack 일괄 검토 대기`

## L5 Ledger

- Issue: https://github.com/Team-Moru/moru-iOS/issues/111
- PR: https://github.com/Team-Moru/moru-iOS/pull/112 (`OPEN`, `DRAFT`)
- Branch: `feat/#111-social-login-release-config`
- Base branch: `feat/#109-optional-login-entry`
- Base SHA: `2c5425b199cff75ec54bd4af5798876d8bc0da2c`
- Worktree: `/private/tmp/moru-ios-l5.7kLsgl`
- 구현 Head SHA: `4dae91010f48960bb34e24855ae71c86528312f7`
- 최종 PR Head: 이 ledger 문서 commit(정확한 SHA는 PR #112 기준)
- Merge SHA: 없음
- 구현 기능:
  - Debug/Release에 Google iOS·Web client ID와 reversed callback scheme 연결
  - Debug/Release에 Kakao Native app key와 callback scheme 연결
  - Apple Bundle/Team/capability를 확인하고 app-side gate를 `YES`로 연결
  - Main·개인정보처리방침·이용약관·고객지원 HTTPS URL을 Info.plist build
    substitution으로 연결
  - `https`, 정확한 host·route와 port·user info·query·fragment 부재를 요구하는
    공개 URL allowlist
  - 로그인 화면의 MORU 홈·개인정보처리방침·이용약관·고객지원 링크와
    VoiceOver 순서 계약
  - Debug/Release 공개 설정, callback, bundle/team, source entitlement와 금지
    runtime secret key 부재를 확인하는 자동 gate
- 공개 Google 설정:
  - iOS client ID:
    `800384412803-r62hbcns8s3jdkjaq5failk863bl19nv.apps.googleusercontent.com`
  - reversed client ID:
    `com.googleusercontent.apps.800384412803-r62hbcns8s3jdkjaq5failk863bl19nv`
  - Web client ID / backend audience:
    `800384412803-it81p3lkv9q9o9cel5sa6imqk1mtrr6m.apps.googleusercontent.com`
  - callback:
    `com.googleusercontent.apps.800384412803-r62hbcns8s3jdkjaq5failk863bl19nv:/oauth`
- 공개 Kakao 설정:
  - Native app key: `35f2ceb3a41aef9369e7de6ad3406685`
  - callback scheme: `kakao35f2ceb3a41aef9369e7de6ad3406685`
  - callback: `kakao35f2ceb3a41aef9369e7de6ad3406685://oauth`
- 공개 Apple metadata:
  - Bundle / Client ID: `com.teammoru.Moru`
  - Team ID: `Z7FSDLFCMK`
  - Key ID metadata: `M88877LL32`
  - Sign in with Apple entitlement: `com.apple.developer.applesignin = Default`
  - App-side gate: `MORU_APPLE_SIGN_IN_ENABLED=YES`
  - Key ID는 서버용 metadata로만 문서화하고 실제 `.p8` private key는 앱·Git에
    추가하지 않음
- 공개 웹 route:
  - Main: `https://team-moru.github.io`
  - Privacy: `https://team-moru.github.io/privacy`
  - Terms: `https://team-moru.github.io/terms`
  - Support: `https://team-moru.github.io/support`
  - 2026-07-27 실제 HTTPS 요청에서 네 route 모두 200 확인
- 주요 계약:
  - 공개 식별자는 provider token·client secret·admin key·private key가 아님
  - provider configuration과 네 공개 URL이 준비되어야 provider 인증을 활성화
  - configuration 결과와 관계없이 `로그인 없이 시작하기`와 기존 local-first
    경로를 유지
  - 로그인 성공 여부와 무관하게 서버 데이터로 로컬 프로필·루틴·기록을
    자동 교체하지 않음
  - SwiftData schema·migration, Local Repository, routine Domain 계약 변경 없음
- 테스트:
  - 관련 signed XCTest 36/36 성공, failed/skipped/expected failure 0
    (`/private/tmp/moru-ios-l5-related.xcresult`)
  - 전체 signed XCTest 396/396 성공, failed/skipped/expected failure 0
    (`/private/tmp/moru-ios-l5-full.xcresult`)
- 빌드·서명:
  - MORU Release iPhone 16, iOS 26.5 Simulator Debug 성공
  - generic iPhone Debug 성공
  - generic iPhone Release 성공
  - Debug/Release built Info.plist에서 공개 설정과 callback을 정확히 확인
  - Debug/Release signed entitlement에서 application identifier, Team ID와
    `com.apple.developer.applesignin = Default` 확인
- 정적 검증:
  - iPhone functional gate 성공
  - SwiftData boundary gate 성공
  - social login release configuration gate 성공
  - source/built Info.plist·entitlement `plutil` 성공
  - `git diff --check` 성공
  - client secret·Kakao admin key·private key·service account·`.p8` 파일과
    key material 저장소 노출 없음
  - SwiftData schema·migration, Local Repository, routine Domain 변경 없음
- visual·accessibility:
  - 운영 provider/UI configuration으로 visual signed XCTest 1/1 성공
    (`/private/tmp/moru-ios-l5-visual-operational.xcresult`)
  - idle·loading·cancel·offline·401·5xx·Keychain·긴 한국어 8상태를 Medium·AX3에서
    각 2회 렌더링해 32개 PNG가 byte-identical임을 확인
  - capture: `/private/tmp/moru-social-login-l5-operational`
  - idle Medium·idle AX3·긴 한국어 AX3 대표 산출물 수동 확인
  - title → local-first 안내 → 상태 → Apple → Google → Kakao → guest →
    Main → Privacy → Terms → Support VoiceOver 순서 계약 테스트 성공
- Figma manifest·export blocker:
  - File key: `vrVBDLEy0UmqlLVfxnUcY9`
  - Login frame node: `2644:2751`
  - URL:
    `https://www.figma.com/design/vrVBDLEy0UmqlLVfxnUcY9/moru--%EB%B3%B5%EC%82%AC---%EB%B3%B5%EC%82%AC-?node-id=2644-2751&t=T66xtzrK6YKuDfCW-1`
  - Keychain API token과 browser canvas/PNG export를 확보하지 못함
  - node API 응답·PNG·before/after/overlay가 없어 구조·수치·asset을 추정하지
    않았으며 exact pixel match를 통과로 기록하지 않음
- 실제 iPhone·backend release blocker:
  - Apple·Google·Kakao 실제 계정 성공·취소·callback 복귀
  - Google consent screen·테스트 계정과 갱신된 ID token의 backend audience 검증
  - Kakao Developers bundle/Login/consent 설정과 backend access token 검증
  - Apple 서버 raw nonce 검증과 provider token revoke 증거
  - 실제 logout·withdrawal·Kakao unlink와 재로그인
  - 앱 재실행 뒤 MORU Keychain session 복원
  - 비행기 모드·네트워크 단절과 실제 backend 401/5xx
  - 공식 provider 버튼과 Medium·AX3·긴 한국어의 실제 VoiceOver 검증
- 리뷰:
  - 로컬 자체 리뷰 완료
  - GitHub review·inline thread와 CI는 최종 ledger head push 후 확인
- CI(ledger 작성 시점):
  - 최종 ledger head push 후 확인
- 전체 stack 최종 검토 입력:
  - L0 #102 → L1 #104 → L2 #106 → L3 #108 → L4 #110 → L5 #112는 모두
    Draft + OPEN
  - 각 PR의 base branch·구현 Head·ledger·CI와 secret 비노출을 순서대로 확인
  - 공개 Google/Kakao 식별자와 callback, Apple capability, 네 공개 웹 route는
    L5에서 연결됐지만 실제 provider E2E 통과 증거는 아님
  - Apple raw nonce/revoke, Google audience, Kakao token 검증과 provider별 실제
    console 설정을 하나의 release readiness checklist로 검토
  - LocalProfile 우선 Main, local-first Source of Truth, 서버 데이터 자동 교체 없음,
    guest 경로, account/server kill switch를 stack 공통 회귀 계약으로 확인
  - 실제 iPhone 3-provider·callback·Keychain·logout/withdrawal·VoiceOver E2E와
    Figma node API·PNG·overlay 기반 exact visual 승인이 끝나기 전 merge하지 않음
  - `DO NOT MERGE — 운영 설정·실기기 검증 대기`

## L5 실제 iPhone QA Note

- 확인 일자: 2026-07-28
- 대상 Head: `0b84241845595b0c4d61f6a8ed7b2fdd4ce6e0f3`
- 기기:
  - iPhone 13 Pro (`iPhone14,2`)
  - iOS `26.5.2`
  - `paired`, manual pairing, wired transport, tunnel connected
  - booted, Developer Mode enabled
- 실제 기기 build·install·launch:
  - 실제 iPhone destination Debug build 성공
  - Apple Development provisioning, Team `Z7FSDLFCMK`, Bundle
    `com.teammoru.Moru` 확인
  - signed entitlement에서 Sign in with Apple `Default` 확인
  - 기존 앱을 uninstall하지 않고 같은 Bundle ID로 덮어 설치
  - 로컬 앱 컨테이너·사용자 데이터 reset 없이 launch 성공
- 진입·로컬 데이터 보존:
  - 기존 LocalProfile이 있어 선택형 로그인 진입 대신 Main 홈으로 이동
  - `오늘의 루틴`, 루틴·이력 navigation을 확인해 기존 local-first UI 유지
  - `마이 > 설정`의 계정 상태는 signed-out
  - destructive reset 없이 `계정 연결` sheet 진입
  - Apple·Google·Kakao 세 provider 버튼 표시 확인
  - Google/Kakao configuration-required 경고가 없어 운영 공개 설정 활성 확인
- provider 실제 기기 matrix:
  - Google:
    - provider 버튼 표시·configuration 활성: 확인
    - SDK/system 인증 surface: 미확인
    - 사용자 취소·MORU 복귀·callback: 미확인
    - 성공·session restore: 사용자 계정 선택/동의 필요
  - Kakao:
    - provider 버튼 표시·configuration 활성: 확인
    - SDK/system 인증 surface: 미확인
    - 사용자 취소·MORU 복귀·callback: 미확인
    - 성공·session restore: 사용자 Talk/계정 인증 필요
  - Apple:
    - provider 버튼 표시·capability 활성: 확인
    - system 인증 surface: 미확인
    - 사용자 취소·MORU 복귀·callback: 미확인
    - 성공·session restore: 사용자 Apple 인증 필요
- 사용자 수동 provider follow-up:
  - Kakao 계정 연결 성공과 `Kakao 계정 연결됨` 상태를 확인
  - Apple 인증 surface 완료 뒤
    `Apple 인증 정보를 확인하지 못했어요. 로컬 데이터는 그대로 사용할 수 있어요.`
    표시
    - `SocialAuthorizationOutcome.failed`의 backend 호출 전 분기
    - 당시 빌드는 credential 누락·인코딩, request context, system authorization
      오류를 구분해 기록하지 않아 정확한 하위 원인은 미확정
  - Google 인증 surface 완료 뒤
    `Google 계정을 연결하지 못했어요. 로컬 데이터는 그대로 사용할 수 있어요.`
    표시
    - ID token adapter 통과 뒤 coordinator catch 분기
    - remote exchange와 local session storage 중 정확한 실패 단계는 당시
      빌드의 로그만으로 미확정
  - Kakao 연결과 로컬 데이터는 logout·unlink·reset·uninstall 없이 보존
- provider surface blocker:
  - iPhone Mirroring 화면 read와 안전한 sheet open은 성공
  - provider sheet 이후 자동 coordinate click이 반복
    `noWindowsAvailable`로 실패
  - 계정 선택·동의·생체 인증과 혼동할 수 있어 임의 좌표 입력을 중단
  - 앱 코드 결함 증거가 아니라 실제 기기 UI automation tooling blocker
- lifecycle·crash:
  - Home 전환 뒤 background에서 MORU PID 유지
  - 종료 없이 foreground launch 뒤 같은 PID와 Main 유지
  - SIGTERM 정상 종료 뒤 cold launch 성공, 새 PID 유지
  - cold launch 뒤 기존 LocalProfile 우선 Main과 `오늘의 루틴` UI 복원
  - `systemCrashLogs`에서 이름에 MORU가 포함된 crash report 0건
  - token 노출 위험을 피하려 device console stream은 수집하지 않음
- 수행하지 않은 동작:
  - account 선택, email/password, OTP, passcode, Face ID/Touch ID
  - provider 동의·권한 승인, account 추가·변경
  - logout(signed-in 성공이 없어 생략)
  - withdrawal·unlink·로컬 reset·앱 삭제
  - 네트워크 토글·기기 설정 변경
- 민감 정보:
  - token, ID/access/refresh token, auth code, nonce를 수집·출력하지 않음
  - provider 계정명·email·사용자 실명을 QA 결과에 기록하지 않음
- 실제 성공 로그인에 필요한 사용자 action:
  - Google: `계정 연결` sheet에서 Google 버튼을 누르고 사용자가 계정
    선택·동의를 직접 완료한 뒤 callback과 cold launch restore 확인
  - Kakao: Kakao 버튼을 누르고 사용자가 Talk/계정 인증을 직접 완료한 뒤
    callback과 cold launch restore 확인
  - Apple: Apple 버튼을 누르고 사용자가 system 인증을 직접 완료한 뒤
    callback과 cold launch restore 확인
  - 각 provider는 성공 전 사용자 취소를 한 번 수행해 MORU 복귀, 오류 미잔류,
    다른 provider 버튼 재활성화를 확인
- 최초 실제 기기 QA 당시 코드 변경·commit·push: 없음
- 후속 진단 보강:
  - Apple 실패 원인을 credential/context/system error의 값 없는 category와
    숫자 error code로 구분
  - 공통 로그인 실패를 `remote_exchange`와 `session_storage`로 구분하고,
    HTTP status·ASCII server error code·transport/keychain 숫자 code만 기록
  - token·authorization code·nonce·provider user ID·error message는 기록하지 않음
  - 집중 XCTest 23건 통과
  - 실제 iPhone이 무선 목록에서 `unavailable`로 전환되어 진단 build의
    덮어 설치·Apple/Google 재시도는 후속 E2E로 유지

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
