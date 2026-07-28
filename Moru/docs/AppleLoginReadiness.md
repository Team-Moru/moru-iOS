# Apple 로그인 출시 계약 점검

- 확인 일자: 2026-07-27
- 기준 문서: `https://moru-api.duckdns.org/v3/api-docs`
- 대상: `POST /auth/login/{provider}`, `DELETE /auth/withdrawal`

## 공개 앱 metadata

- Bundle / Client ID: `com.teammoru.Moru`
- Team ID: `Z7FSDLFCMK`
- Sign in with Apple entitlement: `com.apple.developer.applesignin = Default`
- App-side gate: `MORU_APPLE_SIGN_IN_ENABLED=YES`
- Key ID metadata: `M88877LL32`

Key ID는 서버의 Apple client secret 생성·키 회전 metadata로만 기록합니다. 앱
런타임에 필요하지 않으므로 Info.plist와 build setting에 넣지 않습니다. 실제 `.p8`
private key는 제공받지 않았으며 앱·Git·문서에 저장하지 않습니다.

## 앱에서 완료한 범위

- `SecRandomCopyBytes`로 32자 raw nonce를 생성하고 SHA-256 challenge를 Apple 요청에
  설정한다.
- Apple callback은 identity token, authorization code, raw nonce, Apple
  user identifier가 모두 현재 요청에 묶인 경우에만 공통 로그인 coordinator로
  전달한다.
- 이름과 이메일 scope는 요청하지 않는다.
- Apple user identifier는 계정 credential과 session에 보존하며 token 재발급 뒤에도
  유지한다.
- 앱 시작과 계정 연결 뒤 credential state를 확인한다.
- `credentialRevokedNotification` 수신 시 credential state를 다시 확인하고
  `.revoked`, `.notFound`, `.transferred` 계정의 로컬 서버 세션을 제거한다.
- token, authorization code, raw nonce, provider user identifier는 description과 debug
  output에서 redaction한다.

## 서버 계약 blocker

현재 OpenAPI의 `SocialLoginRequest`는 `token`과 `authorizationCode`만 선언한다.
`rawNonce`와 Apple user identifier 필드는 선언되어 있지 않다. 앱은 서버가
무시하거나 다르게 해석할 수 있는 필드를 추정해 전송하지 않는다.

현재 `DELETE /auth/withdrawal` 성공 응답은 회원 탈퇴 완료 message만 제공한다.
Apple refresh token revoke 수행 여부나 완료 상태를 확인할 필드 또는 별도
endpoint가 없다. 따라서 서버 응답 성공은 MORU 회원 탈퇴 완료로만 해석하며,
Apple token revoke 완료로 기록하지 않는다.

출시 전에 서버가 다음 계약을 OpenAPI에 명시하고 구현해야 한다.

1. Apple 로그인 요청의 raw nonce 필드와 검증 실패 응답
2. 필요하다면 Apple user identifier 필드의 이름, 목적, 검증 규칙
3. Apple 회원 탈퇴 시 provider token revoke 완료를 보장하는 응답 또는 별도
   endpoint
4. 위 계약의 staging E2E와 실제 iPhone 검증

L0 이전에 저장된 Apple credential에는 Apple user identifier가 없다. 이 세션은
하위 호환으로 복원되지만 credential state를 조회할 수 없다. 다음 실제 Apple
재인증에서 identifier를 저장하기 전까지 revoked 상태 자동 정리를 보장하지
않는다. 실제 iPhone의 로그인·취소·재실행·revoked 알림·탈퇴 흐름도 아직
검증하지 않았다.
