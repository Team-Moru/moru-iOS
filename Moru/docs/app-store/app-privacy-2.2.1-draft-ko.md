# MORU 2.2.1 App Privacy·심사 입력 초안

> 상태: **코드와 API 계약을 기준으로 한 내부 초안입니다.** 이 문서는 App Store Connect 입력값이나 공개 개인정보처리방침의 최종본이 아닙니다. 운영자·보관기간·국외 이전 사실을 확인하기 전에는 외부에 게시하거나 제출하지 않습니다.

## 1. 이번 빌드에서 바로잡은 사실

2.2.1은 로그인 계정과 MORU API 서버를 사용합니다. 루틴·실행 기록은 계정에 연결되어 서버와 동기화될 수 있으며, AI 맞춤 기능은 사용자가 별도로 동의한 경우에만 해당 요청 내용을 MORU 서버를 거쳐 Google Gemini API로 보낼 수 있습니다. 이 요청으로 생성된 안내 텍스트는 Google TTS에서 음성으로 변환되고, 결과 오디오는 AWS S3에 저장되어 앱에 사전 서명된 URL로 제공될 수 있습니다. 따라서 이전의 “계정 없음”, “개발자 서버 없음”, “외부 전송 없음” 답변은 이 빌드에 사용할 수 없습니다.

서버 정상 시나리오 검증에서는 신규 루틴의 5개 단계 생성, Gemini → Google TTS → S3 업로드 → 사전 서명 URL 발급, 오디오 `200`/`audio/mpeg`/0바이트 초과, 선택 음성 `ttsId`의 PATCH·GET 일치를 확인했습니다. 이는 서비스 가용성 근거일 뿐 Google·AWS의 실제 보관·학습·로그 정책을 확정하는 근거는 아닙니다.

코드상 Gemini가 될 수 있는 전송은 다음과 같이 fail-closed로 처리됩니다.

| 경로 | 동의가 없을 때 | 동의 후 |
|---|---|---|
| 루틴 그룹 생성·루틴 추가 outbox | 원격 요청을 만들거나 claim하기 전에 로컬에 보류 | 명시적 사용자 동작 뒤에만 재개 |
| 루틴 AI 제안·온보딩 추천 | 서버 호출 없이 로컬 대체 결과 | 서버 추천 요청 가능 |
| 실행 중 AI 단계 요청 | 원격 요청 전에 오류로 차단 | 원격 요청 가능 |
| 동의 철회 | 자동 재시도·exact replay도 보류 | 사용자가 다시 동의한 뒤에만 재개 |

## 2. App Privacy 입력 후보와 build 3 Privacy Report 대조

`수집`은 Apple의 App Privacy 정의에 따라 개발자 또는 통합 제3자가 기기 밖에서 접근할 수 있는 전송을 뜻합니다. 2026-08-17의 clean archive `2.2.1 (3)` Privacy Report는 앱 자체 manifest뿐 아니라 Google Sign-In 9.1.0과 Kakao SDK의 manifest도 표시했습니다. 따라서 아래 SDK 행을 빼고 5개 앱 자체 행만 입력하면 과소신고 위험이 있습니다.

| Apple 데이터 유형 | 코드·archive 근거 | 사용자와 연결 | 목적 | 추적 | 상태 |
|---|---|---:|---|---:|---|
| User ID | 로그인 세션, 서버 member ID, bearer 인증. Google Sign-In manifest도 선언 | 예 | 앱 기능; Google SDK manifest는 분석도 선언 | 아니오 | 보수적 입력 후보 |
| Other User Content | 루틴 제목·설명·단계, 자유 입력/전사문, AI 요청 본문 및 Google TTS로 전달될 수 있는 생성 안내 텍스트 | 예 | 앱 기능, 맞춤화 | 아니오 | 보수적 입력 후보 |
| Product Interaction | 루틴 완료·건너뜀·실행 시각·기간·기상 시각 등 실행 기록 | 예 | 앱 기능 | 아니오 | 보수적 입력 후보 |
| Email Address | Google ID token의 `email`을 `name` 부재 시 닉네임으로 사용할 수 있고, Apple 서버 구현도 email을 닉네임 후보로 읽음. Google Sign-In manifest도 선언 | 예 | 앱 기능 | 아니오 | 보수적 입력 후보; Apple email scope와 실제 저장 범위 재확인 |
| Name | Google ID token의 `name`을 닉네임으로 저장할 수 있음. Google Sign-In manifest도 선언 | 예 | 앱 기능 | 아니오 | 보수적 입력 후보 |
| Phone Number | Google Sign-In 9.1.0 Privacy Report manifest가 선언 | 예 | 앱 기능 | 아니오 | **SDK 선언 후보** — OAuth/SDK 실제 적용 범위를 확인하거나 보수적으로 입력 |
| Coarse Location | Google Sign-In 9.1.0 Privacy Report manifest가 선언 | 예 | 앱 기능 | 아니오 | **SDK 선언 후보** — WeatherKit 위치와 별도로 확인 |
| Device ID | Google Sign-In 9.1.0 Privacy Report manifest가 분석 목적으로 선언 | 예 | 분석 | 아니오 | **SDK 선언 후보** |
| Other Usage Data | Google Sign-In 9.1.0 Privacy Report manifest가 분석 목적으로 선언 | 예 | 분석 | 아니오 | **SDK 선언 후보** |
| Other Data | Google Sign-In manifest는 앱 기능·분석, KakaoSDKCommon manifest는 앱 기능으로 선언 | 예 | 앱 기능; Google SDK manifest는 분석도 선언 | 아니오 | **SDK 선언 후보** |
| Location | 앱은 현재 위치를 WeatherKit에 전달하고 MORU API 서버에는 보내지 않음 | Apple Weather는 위치를 예보 제공에만 사용하고 사용자 식별 정보와 연결·요청 간 추적하지 않는다고 안내 | 날씨 표시 | 아니오 | **ASC 확인 필요** |
| Audio Data / Speech Recognition | 원본 마이크 오디오는 MORU API에 보내는 코드가 없음. Google TTS 결과 오디오는 사용자의 원본 음성이 아니며, Apple 음성 프레임워크의 처리·보관은 Apple 정책 및 설정에 따름 | Apple 서비스 분류 확인 필요 | 음성 단계 입력 | 아니오 | **ASC 분류 확인 필요** |

현재 앱 소스에서 광고 SDK·IDFA 전송·추적은 확인되지 않았고 archive Privacy Report도 모두 `Tracking: NO`입니다. 그러나 Google Sign-In의 기본 `email`·`profile` scope, Google/Kakao 콘솔 동의 항목, 서버가 token claim을 저장·로그하는 범위는 운영 증빙으로 최종 확인해야 합니다. SDK 선언보다 좁게 답하려면 각 SDK 공급자 또는 운영 콘솔의 근거가 필요합니다.

## 3. 앱 번들 Privacy Manifest와 archive 검증

`Moru/PrivacyInfo.xcprivacy`에는 앱 자체 코드 근거의 `Name`, `Email Address`, `User ID`, `Other User Content`, `Product Interaction`을 사용자와 연결됨·추적 아님으로 선언하고, UserDefaults required-reason API(`CA92.1`)를 선언합니다. 이 manifest는 App Store Connect App Privacy 설문을 대체하지 않습니다.

build 3 clean archive에서 다음을 확인했습니다.

1. `Moru.app/PrivacyInfo.xcprivacy`와 포함 SDK manifest 12개가 실제 번들에 있고, root manifest의 `plutil -lint`가 통과했다.
2. Xcode Organizer Privacy Report를 생성했다. 보고서는 Google Sign-In의 Name, Email Address, Phone Number, Coarse Location, User ID, Device ID, Other Usage Data, Other Data와 KakaoSDKCommon의 Other Data를 추가로 표시한다.
3. 업로드된 App Store Connect build `2.2.1 (3)`은 검증됨 상태이고 배포 서명 결과 `get-task-allow: false`, `com.apple.developer.applesignin`, `com.apple.developer.weatherkit` entitlement를 표시한다.

## 4. 공개 정책과 App Review에 확정해야 할 값

다음 사실은 앱 저장소만으로 신뢰성 있게 알 수 없으므로 추정해 쓰지 않습니다.

| 확정할 값 | 필요한 이유 |
|---|---|
| 법적 개인정보처리자명·사업장 주소·개인정보 문의처 | 공개 개인정보처리방침과 App Review 연락처 |
| MORU API DB·백업·접근 로그의 보관 기간 및 삭제 절차 | 이용자 보관·파기 고지와 탈퇴 설명 |
| Google Gemini·Google TTS의 실제 프로젝트/계약 주체, 처리 지역·보관·학습 사용 여부 | AI·음성 제3자 제공·위탁 및 국외 처리 고지 |
| Google TTS 오디오와 AWS S3의 운영 주체·보관·로그 정책 | Gemini → Google TTS → AWS S3 정상 경로와 AWS S3 `ap-northeast-2` 리전은 확인됐으나 실제 운영 보관·백업·로그 정책은 확인 필요 |
| Google OAuth consent screen의 실제 승인 scope, Google Sign-In 9.1.0 manifest 적용 범위, Kakao Developers 동의 항목 | archive Privacy Report는 Google SDK 8개와 Kakao SDK Other Data를 추가로 선언한다. 앱은 Kakao `me()`/프로필 조회를 호출하지 않지만 서버가 token에서 어떤 claim을 저장·로그하는지는 운영 증빙 필요 |
| 심사용 로그인 계정 또는 심사자가 로그인 없이 재현할 수 있는 경로 | App Review Information |

## 5. 2.2.1 심사 메모 초안

심사 메모에는 다음을 사실대로 반영합니다.

* MORU는 선택적 계정 로그인을 제공하며 로그인 후 루틴·실행 기록을 MORU 서버와 동기화할 수 있습니다.
* AI 맞춤 기능은 별도의 “AI 데이터 처리” 화면에서 사용자가 명시적으로 동의해야 활성화됩니다. 동의를 거부하거나 철회하면 해당 AI 전송은 진행하지 않고, 로컬 루틴 기능은 계속 사용할 수 있습니다.
* Apple 계정 탈퇴 중 `AUTH4091`이 발생하면 앱은 로컬/보류 상태를 삭제하지 않고 Sign in with Apple 재인증을 요청한 뒤 정상 탈퇴만 다시 시도합니다.
* WeatherKit 화면의 Apple Weather attribution 재현 및 실제 기기 녹화는 별도로 검증해야 합니다.

## 6. 제출 전 체크

- [ ] 위 미확정 서버·운영 사실을 운영 책임자가 확인했다.
- [ ] 공개 privacy/support/terms 페이지가 이 초안과 같은 사실을 말한다.
- [ ] App Store Connect App Privacy 설문을 위 최종 사실으로 입력했다.
- [ ] review account/로그인 절차 또는 로그인 없이 재현되는 심사 경로를 제공했다.
- [ ] clean archive Privacy Report와 코드/설문을 대조했다.
