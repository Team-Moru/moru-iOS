# Google Login Readiness

## 현재 상태

GoogleSignIn-iOS `9.1.x`와 MORU 로그인 연결에 검증된 공개 OAuth 식별자를 연결했습니다.
Debug와 Release 모두 아래 공개 build setting을 사용하며, 세 값이 유효하고 서로
일치하지 않으면 Google 로그인 버튼과 callback 처리는 동작하지 않습니다.

- `MORU_GOOGLE_IOS_CLIENT_ID`
- `MORU_GOOGLE_SERVER_CLIENT_ID`
- `MORU_GOOGLE_REVERSED_CLIENT_ID`

연결 값은 `Moru/docs/SocialLoginReleaseConfiguration.md`에 기록합니다. client secret,
service account key와 기타 비밀값은 앱·xcconfig·Info.plist·저장소에 넣지 않습니다.

## 외부 구성 blocker

출시 전 Google Cloud Console과 MORU backend 담당자가 다음을 실제 환경에서 확인해야
합니다.

1. bundle ID `com.teammoru.Moru`에 연결된 iOS OAuth client ID
2. iOS client ID를 뒤집은 URL scheme
3. MORU backend가 ID token의 `aud`로 검증할 Web/server OAuth client ID
4. OAuth consent screen과 실제 iPhone 테스트 계정

`GoogleSignInPublicConfiguration`은 다음을 모두 검증합니다.

- iOS와 server client ID가 `.apps.googleusercontent.com` 형식인지
- reversed URL scheme이 iOS client ID의 component 역순과 정확히 일치하는지
- placeholder 또는 비어 있는 값이 아닌지

## 앱·서버 계약

- 앱은 `GoogleSignIn`과 `GoogleSignInSwift` product만 링크합니다.
- 기본 Google 로그인 외 추가 API scope를 요청하지 않습니다.
- 로그인 완료 후 `refreshTokensIfNeeded()`로 갱신한 ID token만
  `POST /auth/login/google`의 `token`으로 전송합니다.
- Google access token, refresh token, profile, email, authorization code는 MORU
  서버 요청에 넣지 않습니다.
- 사용자 취소(`GIDSignInErrorCode.canceled`)는 오류 문구나 서버 요청을 만들지 않습니다.
- MORU 로그아웃과 회원 탈퇴 뒤 Google SDK의 로컬 session도 정리합니다.
- Google callback은 앱 루트 `onOpenURL`에서 `AuthCallbackRouter`를 거쳐 SDK로 전달합니다.

## 실제 기기 검증 대기

실제 client ID와 backend audience가 준비된 뒤 실제 iPhone에서 다음을 검증해야 합니다.

- 공식 Google 버튼 로그인 성공과 취소
- Safari/Google app 전환 뒤 reversed URL callback 복귀
- 만료 임박 token의 refresh와 backend audience 검증 성공
- MORU 로그아웃·회원 탈퇴 뒤 Google SDK session 정리와 재로그인
- 앱 재실행 뒤 MORU Keychain session 복원
- 실패·오프라인에서도 로컬 프로필·루틴·기록 유지

실제 iPhone과 Google Console/backend를 사용하지 않은 로컬 빌드는 위 항목의 통과 증거가
아닙니다.
