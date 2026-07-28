# 소셜 로그인 운영 설정 manifest

- 확인 일자: 2026-07-27
- Issue: `#111`
- 기준: `feat/#109-optional-login-entry@2c5425b199cff75ec54bd4af5798876d8bc0da2c`
- 대상 bundle ID: `com.teammoru.Moru`

## 앱에 연결한 공개 입력

- Google iOS client ID

  `800384412803-r62hbcns8s3jdkjaq5failk863bl19nv.apps.googleusercontent.com`

- Google reversed client ID

  `com.googleusercontent.apps.800384412803-r62hbcns8s3jdkjaq5failk863bl19nv`

- Google Web client ID / backend audience

  `800384412803-it81p3lkv9q9o9cel5sa6imqk1mtrr6m.apps.googleusercontent.com`

- Kakao Native app key: `35f2ceb3a41aef9369e7de6ad3406685`
- Kakao callback scheme: `kakao35f2ceb3a41aef9369e7de6ad3406685`
- Kakao callback: `kakao35f2ceb3a41aef9369e7de6ad3406685://oauth`
- Main: `https://team-moru.github.io`
- Privacy: `https://team-moru.github.io/privacy`
- Terms: `https://team-moru.github.io/terms`
- Support: `https://team-moru.github.io/support`

Debug와 Release는 같은 공개 운영 식별자를 사용합니다. Google client ID 두 개와
Kakao Native app key는 공개 식별자이며, provider token이나 비밀값이 아닙니다.

`AccountEntryPolicyConfiguration`은 `https`, host `team-moru.github.io`, 포트·사용자
정보·query·fragment 없음과 route `/`, `/privacy`, `/terms`, `/support`의 정확한
조합만 허용합니다. 네 URL과 provider별 configuration이 준비된 경우 provider UI를
활성화합니다. configuration 결과와 관계없이 `로그인 없이 시작하기`는
유지합니다.

## Apple 공개 metadata와 capability

| 항목 | 값·상태 |
| --- | --- |
| Bundle / Client ID | `com.teammoru.Moru` |
| Team ID | `Z7FSDLFCMK` |
| Sign in with Apple entitlement | `com.apple.developer.applesignin = Default` |
| App-side gate | `MORU_APPLE_SIGN_IN_ENABLED=YES` |
| Key ID metadata | `M88877LL32` |

Key ID는 서버의 Apple client secret 생성·키 회전 기록용 metadata이며 앱
런타임에는 필요하지 않습니다. 따라서 Key ID와 `.p8` private key를
Info.plist나 build setting에 추가하지 않습니다. 실제 `.p8` 값은 제공받지
않았고 저장소에도 포함하지 않습니다.

## Figma 기준 manifest

- File key: `vrVBDLEy0UmqlLVfxnUcY9`
- Login frame node: `2644:2751`
- URL:
  `https://www.figma.com/design/vrVBDLEy0UmqlLVfxnUcY9/moru--%EB%B3%B5%EC%82%AC---%EB%B3%B5%EC%82%AC-?node-id=2644-2751&t=T66xtzrK6YKuDfCW-1`
- API/PNG source: 미확보
- before/after/overlay: 미수행

현재 macOS Keychain의 `Figma API Token for Codex` 항목을 찾지 못했고 browser
canvas도 빈 화면이어서 node API 응답과 PNG export를 확보하지 못했습니다.
node 구조·수치·asset을 추정하지 않으며 exact pixel match를 통과로 기록하지
않습니다. L4에서 고정한 로그인 화면 구조를 유지하고 Medium·AX3·긴 한국어
deterministic capture와 VoiceOver 순서 회귀만 수행합니다.

## 보안 경계와 미검증 blocker

- Google client secret·service account key를 앱·Git에 저장하지 않습니다.
- Kakao admin key·client secret을 앱·Git에 저장하지 않습니다.
- Apple `.p8` private key를 앱·Git·문서에 저장하지 않습니다.
- provider token, authorization code, raw nonce는 설정이나 문서에 기록하지
  않습니다.
- SwiftData schema·migration, Local Repository, Routine Domain은 변경하지 않습니다.

운영 식별자가 연결되었다는 사실은 provider E2E 통과 증거가 아닙니다. 실제
iPhone의 Apple·Google·Kakao 성공·취소·callback, Google backend audience, Apple
raw nonce와 revoke, Kakao backend token 검증·logout·unlink, Keychain 복원은 계속
release blocker입니다.

## 반복 검증

`bash Scripts/check-social-login-release-config.sh .`은 Debug/Release 공개 build
setting, source Info.plist callback·web key, bundle/team ID, Apple entitlement와
금지된 runtime secret/server metadata key 부재를 함께 확인합니다. built Info.plist와
서명된 entitlement는 Debug/Release 산출물에서 별도로 확인해야 합니다.
