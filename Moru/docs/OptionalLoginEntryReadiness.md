# 선택형 로그인 진입 화면 출시 준비

## 현재 안전 gate

- `LocalProfile`이 있으면 계정 복원·로그아웃·토큰 만료·회원 탈퇴 상태와 관계없이
  Main을 유지합니다.
- `LocalProfile`이 없고 계정 복원 중일 때만 Splash를 유지합니다.
- 복원이 끝난 미로그인·복원 실패 상태는 별도 `AccountEntryView`로 이동합니다.
- 로그인 성공, 이미 로그인된 상태, `로그인 없이 시작하기`는 기존 로컬 온보딩으로
  이동합니다.
- Google/Kakao 공개 configuration이 placeholder이면 해당 공식 버튼을 비활성화하고
  필요한 설정을 화면에 알립니다.
- `MORU_APPLE_SIGN_IN_ENABLED`가 명시적으로 활성화되지 않으면 Apple 공식 버튼도
  비활성화합니다.
- 공개 정책 URL은 `https` URL만 활성화합니다. placeholder나 누락 값은 링크처럼
  동작시키지 않으며, 두 정책 URL이 모두 준비되기 전에는 provider 인증도
  노출하지 않습니다. `로그인 없이 시작하기`는 계속 사용할 수 있습니다.
- 로그인 중에는 provider 버튼과 건너뛰기를 함께 잠가 중복 요청과 뒤늦은 로그인
  완료 경쟁을 막습니다.

## 외부 입력 blocker

### Figma와 asset

- 실행 context에 선택형 로그인 화면의 정확한 Figma node ID가 없습니다.
- 별도 첨부에서 계측 가능한 spacing, typography, asset 원본도 저장소에 없습니다.
- 따라서 기존 MORU pilot token과 제공된 공식 SDK/asset을 사용해 화면 구조와
  상태를 구현했으며 exact pixel match를 통과로 기록하지 않습니다.
- Apple과 Google은 공식 SDK 버튼을 사용하고, Kakao는 저장소에 포함된 공식 한국어
  medium-wide asset을 사용합니다.

### Provider

- Google Cloud iOS/Web OAuth client ID, reversed URL scheme, backend audience가
  필요합니다.
- Kakao Developers Native app key, bundle ID, Kakao Login/동의 설정이 필요합니다.
- Apple Team provisioning, 서버 raw nonce 검증, provider token revoke 확인이
  필요합니다.
- 위 준비를 마친 배포 configuration에서만 `MORU_APPLE_SIGN_IN_ENABLED=YES`로
  설정합니다.
- 실제 provider credential이 없는 빌드는 Google/Kakao 로그인을 의도적으로
  제공하지 않습니다.

### 정책

- `MORU_PRIVACY_POLICY_URL`: 공개 개인정보처리방침 HTTPS URL
- `MORU_TERMS_OF_SERVICE_URL`: 공개 이용약관 HTTPS URL
- 현재 저장소에는 운영 URL이 제공되지 않았으므로 두 링크는 의도적으로
  비활성화됩니다.

## 실제 기기 검증 대기

- iPhone에서 Apple/Google/Kakao 성공·취소·callback 복귀
- 비행기 모드·네트워크 단절과 401/5xx 응답
- Keychain 읽기·저장 실패 뒤 로컬 온보딩 진입
- 로그아웃·토큰 만료·회원 탈퇴 뒤 기존 LocalProfile/Main 유지
- Medium, AX3, 긴 한국어, VoiceOver 순서와 공식 버튼의 실제 접근성 노출
