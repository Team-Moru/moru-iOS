# MORU 개인정보·App Review 답변

## 사실의 출처와 증거 등급

| 등급 | 이 문서에서의 사용 원칙 | 현재 상태 |
|---|---|---|
| 사용자 확정 최종 빌드 사실 | 알람, 온디바이스 음성 코칭, 원본 음성 비저장·비전송, 서버 폴백 없음을 제품·개인정보 문안에 확정형으로 사용 | 확정 |
| 현재 업로드 빌드 관찰값 | 2026-08-05 업로드·제출한 버전 1.0(5), 번들 ID `com.teammoru.Moru`, iPhone, iOS 26.0. WeatherKit attribution 확인 요청으로 반려됨 | 수정 빌드 2.1.1(1)은 archive 검증·업로드·선택 필요 |
| 수정 빌드 예정값 | 2.1.1(1), `com.teammoru.Moru`, iOS 26.0, WeatherKit entitlement. iPad Air 11-inch 시뮬레이터에서 최초 허용 및 설정 복귀 흐름에 Apple 법적 페이지로 연결되는 Apple Weather 결합 마크가 표시됨 | 실제 지원 iPad 녹화·첨부와 App Store Connect 업로드·선택은 미완료 |
| Apple 플랫폼 규칙 | 필드 한도, 연령 등급, 수출 규정, OS 관리 백업 관련 플랫폼 규칙을 2026-07-14 확인 기준으로 적용 | 미래 제출 시 현행 규칙 재확인 |
| 후속 제출 입력·증빙 | 실제 선택 빌드, 계정 값, 권리 문서, 심사 연락처, 수출 규정 최종 분기를 실제 증빙으로 채움 | 미완료 |

## 개인정보 4축 사실표

| 축 | App Privacy 및 제출 답변 | 소비자에게 설명할 사실 |
|---|---|---|
| 개발자·통합 제3자 수집·전송 | Apple App Privacy 정의에서 개발자 또는 통합 제3자 파트너가 접근할 수 있는 기기 밖 전송이 없으므로 수집 없음 | 추적, 광고 수집, 분석 수집이 없음 |
| 앱 자체 인프라 | 개발자 운영 서버, 앱 자체 동기화·클라우드 백업, 서버 폴백이 없음 | 데이터 처리를 위해 개발자 서버로 전송하지 않음 |
| 기기 내 처리·저장 | 원본 음성은 저장하거나 전송하지 않음. 전사문, 자유 입력, 루틴, 단계, 알람, 완료 결과, 로컬 프로필은 기기에 저장 | 음성 처리와 해당 데이터의 보관은 기기 안에서 이루어짐 |
| OS 관리 백업·삭제 | Apple OS의 기기 백업·복원 포함 여부는 사용자의 Apple ID, 기기 설정, OS 정책에 따름. 개발자는 이 백업에 접근하지 않음 | 앱 삭제는 현재 기기의 앱 컨테이너 제거를 뜻하며, 모든 OS 백업의 소멸을 보장하지 않음 |

## App Privacy

### Apple App Privacy 기준 데이터 수집 없음

App Privacy의 데이터 수집은 개발자 또는 통합 제3자 파트너가 접근할 수 있는 기기 밖 전송을 기준으로 판단합니다. MORU는 그와 같은 전송이 없으므로 App Privacy에는 데이터 수집 없음으로 답변합니다. 이 답변은 루틴·전사문·자유 입력·완료 결과가 기기에 로컬로 저장될 수 있다는 사실과 다릅니다. 로컬 저장은 개발자나 통합 제3자가 접근 가능한 기기 밖 수집이 아닙니다.

| App Privacy 질문 | 답변 | 근거 |
|---|---|---|
| 개발자 또는 통합 제3자가 수집하는 데이터가 있는가 | 없음 | 기기 밖 전송 및 접근 가능한 수신자가 없음 |
| 수집한 데이터를 사용자의 신원과 연결하는가 | 해당 없음 | 수집이 없음 |
| 수집한 데이터로 사용자를 추적하는가 | 없음 | 추적, 광고, 분석 수집이 없음 |
| 기기 내 음성·전사문·자유 입력·루틴 결과 | App Privacy 수집으로 신고하지 않음 | 기기 내 처리·저장만 수행하며 원본 음성을 저장·전송하지 않음 |

### 권한 답변

| 권한 | 사용 목적 | 거부 시 영향 | 다시 허용하는 방법 |
|---|---|---|---|
| 마이크 | 기기 안에서 음성 코칭 입력을 처리 | 음성 입력을 사용하는 코칭을 진행할 수 없음 | iOS 설정에서 MORU의 마이크 권한을 다시 허용 |
| 음성 인식 | 기기 안에서 음성 입력을 전사해 단계 진행에 사용 | 음성 인식을 사용하는 코칭을 진행할 수 없음 | iOS 설정에서 MORU의 음성 인식 권한을 다시 허용 |
| AlarmKit | 예약한 알람에서 MORU 루틴을 시작 | 알람 예약·시작을 사용할 수 없음 | iOS 설정에서 MORU의 알람 관련 권한을 다시 허용 |
| 위치 | 사용자가 요청한 현재 위치 날씨를 조회 | 날씨만 사용할 수 없으며 루틴·알람은 계속 사용 가능 | 홈의 `설정에서 위치 권한 켜기`를 눌러 허용하고 앱으로 돌아오면 자동으로 날씨를 다시 조회 |

## 연령 등급 설문 초안

아래는 App Store Connect 설문 입력 전의 답변 초안입니다. 실제 연령 등급은 제출 시 App Store Connect가 계산한 결과를 최종값으로 기록하며, 아래 예상값을 고정 보증으로 사용하지 않습니다.

| 질문군 | 존재 여부 | 빈도 | 근거 | 글로벌 iOS/iPadOS 26+ 예상 | 대한민국 지역 표시 예상 |
|---|---|---|---|---|---|
| Health or Wellness Topics | 있음 | 해당 없음(존재 여부 항목) | 목표에 맞춘 루틴 추천 | 9+ | All |
| 의료 진단·치료 관련 내용 | 없음 | 해당 없음 | 진단·치료 기능을 제공하지 않음 | 등급 상향 요소 없음 | 등급 상향 요소 없음 |
| 광고 | 없음 | 해당 없음 | 광고 제공 없음 | 등급 상향 요소 없음 | 등급 상향 요소 없음 |
| 사용자 생성 콘텐츠·채팅·소셜 기능 | 없음 | 해당 없음 | 다른 사용자가 올린 콘텐츠, 채팅, 소셜 기능 없음 | 등급 상향 요소 없음 | 등급 상향 요소 없음 |
| 무제한 웹 접근 | 없음 | 해당 없음 | 앱 내 자유 웹 탐색 기능 없음 | 등급 상향 요소 없음 | 등급 상향 요소 없음 |
| 성인물·폭력 | 없음 | 해당 없음 | 해당 콘텐츠 없음 | 등급 상향 요소 없음 | 등급 상향 요소 없음 |
| 도박·루트박스 | 없음 | 해당 없음 | 해당 기능 없음 | 등급 상향 요소 없음 | 등급 상향 요소 없음 |

## 수출 규정 결정 트리

외부 통신이 없다는 사실만으로 암호화 미사용을 결론 내리지 않습니다. 실제 제출 전에 최종 빌드와 통합 라이브러리를 기준으로 다음 순서대로 결정합니다.

1. 최종 빌드 또는 통합 라이브러리가 암호화를 사용하거나 암호화 기능에 접근하는지 확인합니다.
2. 사용한다면 Apple OS 내부 기능만 사용하는지, OS 밖의 industry-standard 암호화인지, proprietary·non-standard 암호화인지 분류합니다.
3. 분류별 면제 적용 여부를 확인합니다.
4. 면제되지 않는 경우 수출 규정 문서 업로드 필요 여부를 확인합니다.
5. 미래 제출에서 `ITSAppUsesNonExemptEncryption` 값을 위 판단과 일치하게 확인합니다.

현재 저장소와 2.1.1(1) archive 검증 대상 기준 `ITSAppUsesNonExemptEncryption`은 `false`입니다. 이 관찰값은 수출 규정의 최종 답변이 아니며, 실제 제출 전 최종 빌드와 통합 라이브러리를 기준으로 다시 확인합니다.

## 콘텐츠 권리 증빙 매트릭스

아래 행은 권리 보유를 선결하지 않습니다. 모든 행의 증빙이 완료되기 전에는 App Review의 콘텐츠 권리 답변을 완료로 확정하지 않습니다.

| 자산군 | 구체 범위 | 출처·제작 주체 | 라이선스·양도 근거 | 상업 배포 허용 | attribution 의무 | 증빙 위치 | 책임자 | 상태·완료 증거 |
|---|---|---|---|---|---|---|---|---|
| 앱 코드·SPM | 앱 소스와 의존 패키지 | 증빙 확인 필요 | 증빙 확인 필요 | 미확인 | 미확인 | 미수집 | 책임자 지정 필요 | 미완료 — 라이선스·의존성 증빙 필요 |
| Pretendard·SUIT 폰트 | 앱에 포함되거나 사용되는 폰트 | 증빙 확인 필요 | 증빙 확인 필요 | 미확인 | 미확인 | 미수집 | 책임자 지정 필요 | 미완료 — 폰트 라이선스 증빙 필요 |
| 음성 MP3·TTS 콘텐츠 | 음성 파일과 음성 생성물 | 증빙 확인 필요 | 증빙 확인 필요 | 미확인 | 미확인 | 미수집 | 책임자 지정 필요 | 미완료 — 사용 범위 증빙 필요 |
| UI SVG·PNG | 인터페이스 그래픽 | 증빙 확인 필요 | 증빙 확인 필요 | 미확인 | 미확인 | 미수집 | 책임자 지정 필요 | 미완료 — 원본·라이선스 증빙 필요 |
| 문안 | 스토어·앱·지원 문구 | 증빙 확인 필요 | 증빙 확인 필요 | 미확인 | 미확인 | 미수집 | 책임자 지정 필요 | 미완료 — 작성·사용 권한 증빙 필요 |
| 저장소 밖 앱 아이콘 원본 | Default·Dark·Tinted용 원본 | 증빙 확인 필요 | 증빙 확인 필요 | 미확인 | 미확인 | 미수집 | 책임자 지정 필요 | 미완료 — 원본 권리 증빙 필요 |
| 스크린샷 base·overlay | 최종 빌드 캡처와 오버레이 | 증빙 확인 필요 | 증빙 확인 필요 | 미확인 | 미확인 | 미수집 | 책임자 지정 필요 | 미완료 — 캡처·오버레이 권리 증빙 필요 |

## 기타 제출 답변

| 항목 | 답변 |
|---|---|
| 계정·로그인 | 없음 |
| 결제·인앱 결제·구독 | 없음 |
| 광고·IDFA | 없음 |
| 사용자 생성 콘텐츠 | 없음 |

## App Review 연락처

| 필드 | 붙여넣을 값 |
|---|---|
| 담당자명 | [확정 필요: App Review 담당자명] |
| 이메일 | [확정 필요: App Review 이메일] |
| 전화번호 | [확정 필요: App Review 전화번호] |

## Review Notes

### 붙여넣기 원문

아래 원문은 실기기 녹화 파일을 App Review Information에 첨부한 뒤에만 사용합니다. 첨부 전에는 녹화가 첨부되었다는 문장을 붙여넣지 않습니다.

```
WeatherKit attribution review path (Korean UI labels are quoted):

Version 2.1.1 (1) displays the Apple-provided Apple Weather combined mark whenever WeatherKit data is shown. The mark links directly to Apple's legal attribution page.

1. On a fresh install, complete onboarding. The trial routine opens automatically.
2. Tap "건너뛰기" on each trial step and confirm "건너뛰기". On the result screen, tap "홈으로".
3. On Home, scroll slightly if needed to the "현재 위치 날씨" card.
4. Open Home and allow Location access when the weather prompt appears automatically.
5. Current weather appears with the Apple Weather mark at the bottom-right of the weather card.
6. Tap the Apple Weather mark to open Apple's legal attribution page.

A physical-device screen recording showing these steps is attached in App Review Information as "MORU-2.1.1-1-WeatherKit-Attribution.mov".
No login or test account is required. An active internet connection is required for WeatherKit.
```

| 필드 | 실제값 | 제한 | 결과 |
|---|---:|---:|---|
| Review Notes | 985 UTF-8 bytes | 4,000 UTF-8 bytes 이하 | PASS |

### 반려 메시지 답변 원문

아래 답변도 실기기 녹화 첨부와 2.1.1(1) 빌드 선택을 확인한 뒤 사용합니다.

```
Hello App Review Team,

MORU uses WeatherKit. Version 2.1.1 (1) now displays the Apple-provided Apple Weather combined mark whenever Apple weather data is shown. The mark links directly to Apple's legal attribution page.

We attached a physical-device screen recording in App Review Information showing the WeatherKit feature, the Apple Weather trademark, and opening Apple's legal attribution page.

Thank you.
```

### 심사자 기능 중심 재현 흐름

1. 새로 설치하고 온보딩을 완료합니다.
2. 이어지는 체험 루틴에서 각 단계의 `건너뛰기`를 누르고 확인합니다.
3. 결과 화면에서 `홈으로`를 누릅니다.
4. 홈에서 필요하면 조금 스크롤해 `현재 위치 날씨` 카드를 찾습니다.
5. 홈에 진입하면 자동으로 나타나는 위치 권한 요청을 허용합니다.
6. 현재 기온·상태와 Apple Weather 상표가 함께 표시되는지 확인합니다.
7. 카드 오른쪽 하단의 Apple Weather 마크를 눌러 Apple이 제공한 법적 고지 페이지가 열리는지 확인합니다.
8. 이 전체 흐름을 지원되는 실제 iPad에서 녹화하고 `MORU-2.1.1-1-WeatherKit-Attribution.mov`라는 이름으로 App Review Information에 첨부합니다.

로그인, 외부 계정, 테스트 서버는 필요하지 않습니다. WeatherKit 조회에는 활성 인터넷 연결이 필요합니다.
## 공식 근거

아래 외부 플랫폼 규칙은 2026-07-14에 확인했으며, 실제 제출 시 Apple의 현행 규칙과 App Store Connect 결과를 다시 확인합니다.

| 적용한 외부 주장 | Apple 공식 출처 |
|---|---|
| App Privacy의 수집·추적 답변 | https://developer.apple.com/app-store/app-privacy-details/ |
| 연령 등급 설문 값·정의 및 지역별 결과 | https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions |
| 수출 규정 판단 절차 | https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance |
| 암호화 문서·면제 판단 | https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation |
| Review Notes를 포함한 플랫폼 버전 정보 | https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/ |
| WeatherKit attribution 및 Apple Weather 상표·법적 링크 요구사항 | https://developer.apple.com/weatherkit/ |
| WeatherKit이 제공하는 attribution 자산과 legal page URL | https://developer.apple.com/documentation/weatherkit/weatherattribution |
| AlarmKit 알람 예약 안내 | https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit |
| 대한민국 규정 준수 정보 | https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-korea-compliance-information |
| OS 관리 백업의 파일 시스템 맥락 | https://developer.apple.com/documentation/foundation/using-the-file-system-effectively |
