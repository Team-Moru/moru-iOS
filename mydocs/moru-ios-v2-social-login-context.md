# MORU iOS v2 Social Login 실행 Context

- 마지막 갱신: 2026-07-27
- 상태: `L0_FROZEN_OPEN_DRAFT`
- 고정 계획: `mydocs/moru-ios-v2-social-login-plan.md`
- 원본 계획: `/Users/minhyeok/Downloads/PLAN (5).md`
- v2 context:
  `/Users/minhyeok/Developer/projects/moru-iOS/mydocs/moru-ios-v2-local-first-server-expansion-context.md`

## 실행 기준

- 저장소: `Team-Moru/moru-iOS`
- L0 base branch: `feat/#92-account-lifecycle`
- L0 base SHA: `e4ea5b1fd3e8397b1897ae6adf89958f59cd6266`
- Worktree: `/private/tmp/moru-ios-l0.4wP3Fn`
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
