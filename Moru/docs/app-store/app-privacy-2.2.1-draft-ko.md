# MORU 2.2.1 App Privacy·심사 입력 초안

> 상태: **내부 검증용 초안입니다.** 이 문서는 App Store Connect 입력값이나 공개 개인정보처리방침의 최종본이 아닙니다. 2026-08-17에 제공된 운영 사실을 반영했지만, 법적 운영자·국외 처리·연락처·약관 사실을 확정하기 전에는 외부에 게시하거나 ASC에 저장하지 않습니다.

## 1. 이번 빌드에서 바로잡은 사실

2.2.1은 로그인 계정과 MORU API 서버를 사용합니다. 루틴·실행 기록은 계정에 연결되어 서버와 동기화될 수 있으며, AI 맞춤 기능은 사용자가 별도로 동의한 경우에만 해당 요청 내용을 MORU 서버를 거쳐 Google Gemini API로 보낼 수 있습니다. 이 요청으로 생성된 안내 텍스트는 Google TTS에서 음성으로 변환되고, 결과 오디오는 AWS S3에 저장되어 앱에 사전 서명된 URL로 제공될 수 있습니다. 따라서 이전의 “계정 없음”, “개발자 서버 없음”, “외부 전송 없음” 답변은 이 빌드에 사용할 수 없습니다.

서버 정상 시나리오 검증에서는 신규 루틴의 5개 단계 생성, Gemini → Google TTS → S3 업로드 → 사전 서명 URL 발급, 오디오 `200`/`audio/mpeg`/0바이트 초과, 선택 음성 `ttsId`의 PATCH·GET 일치를 확인했습니다. 이는 서비스 가용성 근거일 뿐 Google·AWS의 실제 보관·학습·로그 정책을 확정하는 근거는 아닙니다.

## 1.1 운영 담당자가 확인한 처리·보관 사실

* 선택 Apple·Google·Kakao 로그인에서는 로그인 제공자, 소셜 계정 고유 ID, 닉네임을 처리한다. Google 또는 Apple 로그인에서 이메일을 닉네임으로 사용할 수 있어 이메일도 처리할 수 있다.
* Kakao Access Token, Google ID Token, Apple Identity Token은 DB에 저장하지 않는다. 일반 MORU refresh token은 해시로 Redis에 최대 14일 보관하고, 재발급·로그아웃·탈퇴 시 삭제한다. Apple 탈퇴용 암호화된 refresh credential은 Apple revoke 성공 뒤 삭제하며, 실제 저장 위치·최대 보관 기간은 공개 정책 전에 확정한다.
* 로그인 뒤 루틴, 단계, 알람·실행 기록, 선택 음성, 사용자 입력, AI 응답, TTS 안내 문구를 계정과 연결해 동기화·서비스 제공 목적으로 처리한다.
* AI는 별도 동의 후에만 사용한다. 사용자 답변, 루틴 제목·단계, AI 루틴 생성 요청 문구는 MORU 서버를 거쳐 Gemini에 전달될 수 있다. 이메일, 소셜 계정 ID, MORU 회원 ID, 원본 음성 파일은 Gemini에 전달하지 않는다.
* Gemini 무료 등급에서는 입력·생성 응답이 Google 제품·서비스 및 머신러닝 기술 개선에 사용될 수 있고, 품질 검토를 위해 사람이 검토할 수 있다. 남용 탐지 로그는 최대 55일 보관될 수 있다.
* AI 안내 문구와 선택 음성 코드는 Google Cloud TTS에 전달될 수 있다. 생성 MP3는 AWS S3에 저장하고 최대 60분 유효한 presigned URL로 제공한다. 운영 기준상 TTS 텍스트와 생성 음성은 학습용으로 별도 기록·재사용하지 않는다.
* CloudWatch 로그는 14일 뒤 자동 삭제하고 Nginx 로그는 일 단위 순환 후 최대 14일 보관한다. OAuth/JWT, AI 입력·응답 원문, 루틴명·자유 입력, 이메일·소셜 계정 ID는 기록하지 않으며 요청 추적 ID·최소 오류 코드·처리 상태를 사용한다.
* 회원 탈퇴 또는 루틴 삭제 시 연결 TTS MP3와 프로필 이미지 S3 객체를 삭제한 뒤 회원·루틴·실행 기록·입력·AI 응답·TTS 정보·구독·약관 동의·토큰 및 Redis 데이터를 삭제한다. S3 삭제나 Apple revoke 실패 시 탈퇴 완료로 처리하지 않고 재시도 가능한 오류를 반환한다. 회원 연결 Redis·S3 데이터는 즉시 삭제하고 RDS 자동 백업에는 최대 1일 남을 수 있으며 수동 스냅샷은 없다.

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
| Other User Content | 루틴 제목·설명·단계, 자유 입력/전사문, AI 요청 본문 및 Google TTS로 전달될 수 있는 생성 안내 텍스트 | 예 | 앱 기능, 맞춤화, 기타 목적 | 아니오 | Gemini 무료 등급의 제품/ML 개선·사람 검토 가능성을 포함한 보수적 입력 후보 |
| Product Interaction | 루틴 완료·건너뜀·실행 시각·기간·기상 시각 등 실행 기록 | 예 | 앱 기능 | 아니오 | 보수적 입력 후보 |
| Email Address | Google ID token의 `email`을 `name` 부재 시 닉네임으로 사용할 수 있고, Apple 서버 구현도 email을 닉네임 후보로 읽음. Google Sign-In manifest도 선언 | 예 | 앱 기능 | 아니오 | 보수적 입력 후보; Apple email scope와 실제 저장 범위 재확인 |
| Name | Google ID token의 `name`과 Kakao token을 받은 서버의 사용자 정보 API 프로필 닉네임을 계정 닉네임으로 저장할 수 있음. Google Sign-In manifest도 선언 | 예 | 앱 기능 | 아니오 | 보수적 입력 후보 |
| Phone Number | Google Sign-In 9.1.0 Privacy Report manifest가 선언 | 예 | 앱 기능 | 아니오 | **SDK 선언 후보** — OAuth/SDK 실제 적용 범위를 확인하거나 보수적으로 입력 |
| Coarse Location | Google Sign-In 9.1.0 Privacy Report manifest가 선언 | 예 | 앱 기능 | 아니오 | **SDK 선언 후보** — WeatherKit 위치와 별도로 확인 |
| Device ID | Google Sign-In 9.1.0 Privacy Report manifest가 분석 목적으로 선언 | 예 | 분석 | 아니오 | **SDK 선언 후보** |
| Other Usage Data | Google Sign-In 9.1.0 Privacy Report manifest가 분석 목적으로 선언 | 예 | 분석 | 아니오 | **SDK 선언 후보** |
| Other Data | Google Sign-In manifest는 앱 기능·분석, KakaoSDKCommon manifest는 앱 기능으로 선언 | 예 | 앱 기능; Google SDK manifest는 분석도 선언 | 아니오 | **SDK 선언 후보** |
| Exact Location | 앱은 현재 위치를 WeatherKit에 전달하고 MORU API 서버에는 보내지 않음 | 아니오 | 해당 없음 | 아니오 | 현재 근거로 App Privacy 추가 신고 대상 아님 |
| Audio Data | 원본 마이크 오디오는 MORU API·Gemini에 보내거나 저장하지 않음. Google TTS 결과는 사용자의 원본 음성이 아님 | 아니오 | 해당 없음 | 아니오 | 현재 근거로 App Privacy 추가 신고 대상 아님 |

현재 App Privacy 입력의 최종 후보는 Name, Email Address, Phone Number, Coarse Location, User ID, Device ID, Other Usage Data, Other Data, Other User Content, Product Interaction의 10개 행이며, 모두 linked·not tracking으로 입력한다. 목적은 Google Sign-In 9.1.0/Kakao SDK manifest와 위 표를 대조해 입력한다. 앱 소스에서 광고 SDK·IDFA 전송·추적은 확인되지 않았고 archive Privacy Report도 모두 `Tracking: NO`입니다. Google/Kakao OAuth 실제 scope 또는 로그 처리 범위가 달라지면 signed Privacy Report와 다시 대조한다.

## 3. 앱 번들 Privacy Manifest와 archive 검증

현재 release source의 `Moru/PrivacyInfo.xcprivacy`에는 앱 자체 코드 근거의 `Name`, `Email Address`, `User ID`, `Other User Content`, `Other Data`, `Product Interaction`을 사용자와 연결됨·추적 아님으로 선언한다. `Other User Content`에는 앱 기능·제품 맞춤화·기타 목적을, `Other Data`에는 앱 기능을 선언하고 UserDefaults required-reason API(`CA92.1`)도 선언한다. SDK 행은 Google/Kakao manifest가 담당하며, 이 manifest는 App Store Connect App Privacy 설문을 대체하지 않는다.

build 3 clean archive에서 다음을 확인했습니다.

1. `Moru.app/PrivacyInfo.xcprivacy`와 포함 SDK manifest 12개가 실제 번들에 있고, root manifest의 `plutil -lint`가 통과했다.
2. Xcode Organizer Privacy Report를 생성했다. 보고서는 Google Sign-In의 Name, Email Address, Phone Number, Coarse Location, User ID, Device ID, Other Usage Data, Other Data와 KakaoSDKCommon의 Other Data를 추가로 표시한다.
3. 업로드된 App Store Connect build `2.2.1 (3)`은 검증됨 상태이고 배포 서명 결과 `get-task-allow: false`, `com.apple.developer.applesignin`, `com.apple.developer.weatherkit` entitlement를 표시한다.

build 3은 현재의 `Other Data` 선언 및 Gemini 무료 등급에 따른 `Other` 목적 변경 전 산출물이므로 제출에 사용하지 않는다. build 4 이상 clean archive에서 manifest·서명·entitlements·Privacy Report를 다시 대조해야 한다.

## 4. 공개 정책과 App Review에 확정해야 할 값

다음 사실은 앱 저장소만으로 신뢰성 있게 알 수 없으므로 추정해 쓰지 않습니다.

| 확정할 값 | 필요한 이유 |
|---|---|
| 법적 개인정보처리자명·사업장 주소·개인정보 문의처 | 공개 개인정보처리방침과 App Review 연락처 |
| Gemini·Google Cloud TTS·AWS·MORU 인프라의 실제 계약 상대방, 처리 국가/리전·국외 처리 근거 | AI·음성 제3자 처리와 국외 이전 고지. 보관·삭제 운영 사실은 확보했지만 법적 고지에는 실제 상대방과 처리 장소가 필요 |
| Apple 탈퇴용 encrypted refresh credential의 실제 저장 위치와 최대 보관 기간 | 일반 refresh token의 Redis 14일과 구분해 탈퇴·파기 고지 필요 |
| Nginx/ALB/CloudWatch의 원본 IP·User-Agent 처리 여부와 프로필 이미지 수집 경로 | App Privacy 및 공개 보관·삭제 범위 대조 |
| Google OAuth consent screen의 실제 승인 scope, Google Sign-In 9.1.0 manifest 적용 범위, Kakao Developers 동의 항목 | archive Privacy Report는 Google SDK 8개와 Kakao SDK Other Data를 추가로 선언하므로 실제 콘솔·운영 범위와 대조 필요 |
| 결제·구독·환불, 아동 정책, 준거법/관할, 약관 변경, AI 결과·사용자 입력의 권리·책임 | 공개 이용약관 |
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
