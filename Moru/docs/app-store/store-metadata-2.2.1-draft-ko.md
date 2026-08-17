# MORU 2.2.1 App Store Connect 메타데이터·심사 정보 초안

> 상태: **로컬 초안 — 아직 App Store Connect에 입력하거나 저장하지 않았습니다.** 2026-08-17에 읽기 전용으로 확인한 현재 1.0 메타데이터의 “계정 가입 없음”, “WeatherKit 제거”, “로그인·테스트 계정 불필요” 문구는 2.2.1에 사용하면 안 됩니다.

## 1. 2.2.1에 반영할 검증된 사실

* Apple·Google·Kakao 로그인을 제공하며, 로그인한 계정의 루틴·실행 기록·선택 설정은 MORU API 서버와 동기화될 수 있습니다.
* AI 맞춤 루틴·추천·AI 단계는 별도 `AI 데이터 처리` 화면의 명시적 동의가 있어야 합니다. 거부·철회하면 Gemini 전송과 자동 재시도가 중단되고 로컬 루틴 기능은 계속 사용할 수 있습니다.
* 동의한 AI 요청은 MORU 서버를 거쳐 Google Gemini로 전송될 수 있으며, 생성된 안내 텍스트는 Google TTS로 음성화되어 AWS S3의 사전 서명 URL로 제공될 수 있습니다.
* WeatherKit 현재 위치 날씨 기능과 `com.apple.developer.weatherkit` entitlement가 포함됩니다. 위치 권한을 거부해도 루틴과 알람은 사용할 수 있습니다.
* Apple 계정 탈퇴에서 `AUTH4091`이 발생하면 Sign in with Apple 재인증을 요청하고, 취소·실패 시 로컬 데이터·보류 상태를 삭제하거나 로그아웃하지 않습니다.

## 2. 입력 후보

### 프로모션 텍스트

```text
알람·루틴·기록을 하나로 관리하고, 선택 시 계정 동기화와 AI 맞춤 루틴을 사용할 수 있어요.
```

### 설명

```text
알람을 끄는 순간, 오늘의 루틴을 시작하세요. 모루는 알람과 루틴, 수행 기록을 하나의 흐름으로 연결하는 루틴 앱입니다.

■ 알람에서 바로 시작하는 루틴
원하는 요일과 시간에 알람을 설정하고, 알람에서 오늘의 루틴으로 자연스럽게 이어갈 수 있어요.

■ 루틴 만들기와 수행 기록
루틴의 이름·단계·소요 시간·반복 요일을 직접 설정하고, 완료·건너뜀·수행 기록을 확인하세요.

■ 음성 안내와 입력
기기 내장 음성 또는 로그인 후 사용할 수 있는 서버 생성 음성으로 단계를 안내받을 수 있어요. 음성 단계 입력을 사용하면 iPhone의 마이크와 음성 인식 권한이 필요할 수 있습니다.

■ 선택적 계정 동기화
Apple, Google 또는 Kakao로 로그인하면 루틴·수행 기록·선택한 설정이 MORU 서버와 동기화될 수 있습니다.

■ 선택적 AI 맞춤 기능
AI 맞춤 루틴·추천·AI 단계를 처음 사용하기 전, 어떤 텍스트가 외부 AI 처리로 전송될 수 있는지 안내하고 별도 동의를 받습니다. 동의하지 않아도 로컬에서 루틴을 만들고 사용할 수 있습니다.

■ 현재 위치 날씨
사용자가 위치 권한을 허용한 경우에만 홈 화면에 현재 위치 날씨를 표시합니다. 위치를 거부해도 루틴과 알람은 계속 사용할 수 있습니다.

개인정보 처리와 외부 서비스에 관한 자세한 내용은 개인정보처리방침을 확인해 주세요.
```

### URL과 권리 정보

| ASC 필드 | 입력 전 조건 |
|---|---|
| 지원 URL | 공개 `support` 페이지를 2.2.1 사실로 게시한 뒤 동일 URL을 사용 |
| 개인정보처리방침 URL | 법적 운영자·문의처·보존/파기·Google/AWS 처리 정보를 확정해 `privacy` 페이지를 게시한 뒤 사용 |
| 이용약관 URL | 법적 운영자·분쟁/책임 조항을 확정해 `terms` 페이지를 게시한 뒤 사용 |
| 저작권 | 실제 권리자 표기와 폰트·음성·이미지 라이선스 증빙 확인 후 입력 |

## 3. App Privacy 입력 후보

최종 값은 공개 개인정보처리방침과 signed archive Privacy Report를 대조한 뒤 입력합니다.

| Apple 데이터 유형 | 연결됨 | 목적 | 추적 |
|---|---:|---|---:|
| Name | 예 | 앱 기능 | 아니오 |
| Email Address | 예 | 앱 기능 | 아니오 |
| User ID | 예 | 앱 기능 | 아니오 |
| Other User Content | 예 | 앱 기능, 맞춤화 | 아니오 |
| Product Interaction | 예 | 앱 기능 | 아니오 |
| Location | WeatherKit 및 Apple 정책 기준을 확정 후 입력 | 앱 기능 | 아니오 |
| Audio Data / Speech Recognition | 원본 마이크 오디오와 서버 생성 TTS 결과를 Apple 분류에 맞게 최종 검토 | 앱 기능 | 아니오 |

추적·광고·IDFA 전송은 현재 앱 소스에서 확인되지 않았습니다. 이 표는 Apple의 App Privacy 설문을 대체하지 않습니다.

## 4. App Review Information 초안

### 로그인 정보

`로그인 필요`로 표시하고, 심사자가 Apple/Google/Kakao 로그인 및 서버 생성 음성을 재현할 수 있는 전용 심사용 계정을 제공해야 합니다. 현재는 계정이 없으므로 이 항목을 입력·제출할 수 없습니다.

### 심사 메모 후보

```text
MORU supports local routine creation without signing in. Signing in with Apple, Google, or Kakao enables account synchronization and server-generated voice features.

For AI-customized routines, recommendations, and AI steps, the app first presents the “AI Data Processing” consent screen. If consent is declined or withdrawn, the app does not send the AI request and local routine features remain available. If consent is granted, the request may be processed by MORU’s server and Google Gemini; generated guidance text may be converted to audio by Google TTS and delivered through AWS S3.

WeatherKit is used only after the user grants location access. The Apple Weather attribution mark is visible with weather data and opens Apple’s legal attribution page.

For account deletion, an AUTH4091 response prompts Sign in with Apple reauthentication. Cancelling or failing reauthentication preserves local data and the pending deletion state.

Review account:
Username: [provide]
Password: [provide]
Sign-in instructions: [provide]
```

`[provide]` 값이 채워지기 전에는 위 메모를 App Store Connect에 저장하거나 심사를 제출하지 않습니다.

## 5. 현재 ASC에서 반드시 교체할 1.0 값

* 설명의 “계정 가입 없이”, “모든 데이터는 기기에만 저장” 문구
* 현재 WeatherKit·위치 권한·WeatherKit entitlement가 없다고 주장하는 심사 메모
* “로그인 필요” 해제 및 “로그인·테스트 계정 불필요” 전제
* 사실과 충돌하는 공개 지원/개인정보/이용약관 URL 내용
