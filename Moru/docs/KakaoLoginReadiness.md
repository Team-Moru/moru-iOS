# Kakao 로그인 출시 준비

## 저장소에 반영된 범위

- Kakao iOS SDK `2.28.0..<2.29.0`
- 앱 target의 최소 `KakaoSDKCommon`, `KakaoSDKAuth`, `KakaoSDKUser` 제품
- `kakaokompassauth` 앱 실행 allowlist
- `kakao{NATIVE_APP_KEY}` callback URL scheme과 SwiftUI root callback
- 카카오톡 설치 시 카카오톡 로그인, 미설치 시 카카오계정 로그인
- 사용자 취소를 조용히 종료하며 카카오계정 로그인으로 자동 fallback하지 않는
  흐름
- Kakao access token만 MORU `POST /auth/login/kakao`의 `token`으로 전달
- 일반 로그아웃의 Kakao SDK `logout()`과 회원 탈퇴의 `unlink()` 분리

## 공개 configuration gate

Debug와 Release의 저장소 기본값은 확인된 아래 공개 식별자입니다.

- Native app key: `35f2ceb3a41aef9369e7de6ad3406685`
- callback scheme: `kakao35f2ceb3a41aef9369e7de6ad3406685`

앱은 다음 조건을 모두 만족할 때만 Kakao SDK를 초기화하고 로그인·callback을
허용한다.

1. `MoruKakaoNativeAppKey`가 공백이나 build setting 표현식 또는 placeholder가 아니다.
2. Native app key가 32자리 16진수다.
3. `MoruKakaoURLScheme`이 대소문자를 제외하고 정확히
   `kakao{NATIVE_APP_KEY}`와 일치한다.

Native app key는 공개 식별자입니다. Admin key, client secret, 토큰은 앱
configuration에 추가하지 않습니다.

## 출시 blocker

- Kakao Developers iOS 플랫폼의 `com.teammoru.Moru` bundle ID 등록 재확인
- Kakao 로그인 활성화와 필수 동의항목 설정 확인
- 개발·운영 앱 분리 정책 확인
- MORU backend가 Kakao access token을 검증하는 실제 E2E 확인
- Kakao Developers 공식 Korean medium-wide PNG의 최종 화면 크기 검수

## 실제 기기 검증 대기

- Kakao Talk 설치 기기에서 Talk 로그인 성공·사용자 취소·callback 복귀
- Kakao Talk 미설치 기기에서 Kakao Account 로그인 성공·사용자 취소
- Talk 로그인 실패 또는 취소 뒤 Account 로그인이 자동 실행되지 않는지 확인
- 로그인 성공 뒤 MORU 서버에 access token만 전달되는지 확인
- 일반 로그아웃 뒤 SDK token 정리와 재로그인
- 회원 탈퇴 성공 뒤 Kakao 연결 해제와 재로그인 동의 화면
- 앱 재실행 뒤 MORU Keychain session 복원

실제 key와 console 설정이 없는 placeholder build에서는 위 항목을 통과로
기록하지 않는다.
