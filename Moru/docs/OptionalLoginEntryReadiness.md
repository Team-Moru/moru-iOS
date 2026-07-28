# 선택형 로그인 진입 화면 출시 준비

## 현재 안전 gate

- `LocalProfile`이 있으면 계정 복원·로그아웃·토큰 만료·회원 탈퇴 상태와 관계없이
  Main을 유지합니다.
- `LocalProfile`이 없고 계정 복원 중일 때만 Splash를 유지합니다.
- 복원이 끝난 미로그인·복원 실패 상태는 별도 `AccountEntryView`로 이동합니다.
- 로그인 성공, 이미 로그인된 상태, `로그인 없이 시작하기`는 기존 로컬 온보딩으로
  이동합니다.
- Debug/Release에 검증된 Google/Kakao 공개 식별자를 연결해 공식 버튼과 callback
  route를 활성화합니다.
- Sign in with Apple capability와 Team/Bundle metadata를 확인하고
  `MORU_APPLE_SIGN_IN_ENABLED=YES`로 연결합니다.
- Main·개인정보처리방침·이용약관·고객지원 URL은 `https://team-moru.github.io`의
  허용된 네 route만 활성화합니다. 네 URL이 모두 준비되기 전에는 provider 인증도
  노출하지 않습니다. `로그인 없이 시작하기`는 계속 사용할 수 있습니다.
- 로그인 중에는 provider 버튼과 건너뛰기를 함께 잠가 중복 요청과 뒤늦은 로그인
  완료 경쟁을 막습니다.

## 외부 입력 blocker

### Figma와 asset

- Figma file key는 `vrVBDLEy0UmqlLVfxnUcY9`, 로그인 frame node는 `2644:2751`입니다.
- Keychain API token과 browser canvas/PNG export를 확보하지 못해 계측 가능한
  spacing, typography, asset 원본은 여전히 없습니다.
- 따라서 node를 추정 변경하지 않고 기존 로그인 화면 구조와 MORU token을 유지하며
  exact pixel match를 통과로 기록하지 않습니다.
- Apple과 Google은 공식 SDK 버튼을 사용하고, Kakao는 저장소에 포함된 공식 한국어
  medium-wide asset을 사용합니다.

### Provider

- Google iOS/Web client ID와 reversed URL scheme, Kakao Native app key와 callback,
  Apple Bundle/Team/capability의 공개 앱 입력은 연결했습니다.
- Google consent와 backend audience 검증, Kakao bundle/Login/동의와 backend token
  검증, Apple 서버 raw nonce와 provider token revoke는 실제 환경에서 확인해야 합니다.
- 공개 configuration 연결만으로 실제 provider E2E를 통과로 기록하지 않습니다.

### 정책

- Main: `https://team-moru.github.io`
- 개인정보처리방침: `https://team-moru.github.io/privacy`
- 이용약관: `https://team-moru.github.io/terms`
- 고객지원: `https://team-moru.github.io/support`
- 다른 host·route와 port·user info·query·fragment가 포함된 URL은 거부합니다.

## 실제 기기 검증 대기

- iPhone에서 Apple/Google/Kakao 성공·취소·callback 복귀
- 비행기 모드·네트워크 단절과 401/5xx 응답
- Keychain 읽기·저장 실패 뒤 로컬 온보딩 진입
- 로그아웃·토큰 만료·회원 탈퇴 뒤 기존 LocalProfile/Main 유지
- Medium, AX3, 긴 한국어, VoiceOver 순서와 공식 버튼의 실제 접근성 노출
