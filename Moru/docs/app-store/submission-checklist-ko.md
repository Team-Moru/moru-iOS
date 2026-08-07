# MORU App Store 제출 체크리스트

> **v1 출시 실행용 문서입니다.** 완료 증거가 확인된 작업만 완료로 표시하며, 실제 계정 값·권리 증빙·제출 결과가 필요한 항목은 담당자가 확인하기 전까지 미완료로 유지합니다.

## 미래 제출 14단계

| 단계 | 구분 | 입력·결정 | 출처 문서 | 선행조건 | 책임자 | 상태 | 완료 증거 |
|---:|---|---|---|---|---|---|---|
| 1 | 필수 | 최신 계약 동의와 App Store Connect 역할·접근 권한 확인 | 이 체크리스트 | 제출 계정에 접근 가능한 실제 담당자 | 계정 책임자 | ☐ 미완료 | 최신 계약 동의와 필요한 역할이 확인된 계정 화면 |
| 2 | 필수 | 앱 레코드에 Name, Primary Language=Korean, Bundle ID, SKU, User Access를 실제 계정 값으로 확인·입력 | `metadata-ko.md`, `privacy-and-review-ko.md` | 1단계 완료, 실제 계정 값 확인 | 출시 책임자 | ☐ 미완료 | 생성된 앱 레코드와 입력값 확인 화면 |
| 3 | 조건부 | 개발자 계정의 대한민국 소재 여부와 개인·조직 유형을 확인. 적용 시 조직은 회사명·이메일·전화·BRN, 개인은 이메일·BRN의 계정 검증을 완료. 건강 및 피트니스 앱의 RCN·GRAC 적용 여부도 카테고리·콘텐츠 조건에 따라 판단 | 이 체크리스트, `metadata-ko.md` | 2단계의 실제 계정·카테고리 값 | 계정·규정 책임자 | ☐ 미완료 | 적용 여부 판단과 계정 검증 완료 증거 |
| 4 | 필수 | 콘텐츠 권리 증빙 매트릭스의 모든 자산군 완료 및 App Review 권리 답변 확정 | `privacy-and-review-ko.md` | 앱 코드·SPM, 폰트, 음성, UI, 문안, 아이콘, 스크린샷 base·overlay의 증빙 수집 | 권리 책임자 | ☐ 미완료 | 매트릭스 전 행의 라이선스·양도·상업 배포·attribution 증빙 |
| 5 | 필수 | **pre-build asset gate:** 저장소 밖 아이콘 원본의 권리·형식 확인, Default·Dark·Tinted 규칙 검수, Xcode 적용, archive 검수 | `screenshots-ko.md`, `privacy-and-review-ko.md` | 4단계 아이콘 권리 증빙 완료 및 현행 Apple 앱 아이콘 규칙 재확인 | 빌드·자산 책임자 | ☐ 미완료 | 변형별 원본·권리·형식 검수, 현행 Apple 앱 아이콘 규칙 재확인, 적용된 archive 증거 |
| 6 | 필수 | 실제 제출 빌드를 업로드·선택한 뒤 version/build, bundle ID, device family, minimum OS 확인 | `privacy-and-review-ko.md`, `support-ko.md` | 5단계 완료 및 실제 제출용 archive | 빌드·출시 책임자 | ☐ 미완료 | 2026-08-06 수정 빌드 1.0(6)의 로컬 archive·App Store Connect export와 배포 서명·WeatherKit entitlement 검증 완료. App Store Connect 업로드·처리·빌드 선택과 값 확인은 미완료 |
| 7 | 필수 | 앱 정보·카테고리·대한민국 가용성·가격·release mode 결정 | `metadata-ko.md` | 2단계 앱 레코드와 실제 출시 결정 | 출시 책임자 | ☐ 미완료 | 저장된 앱 정보와 실제 가격·release mode 결정 증거 |
| 8 | 필수 | 한국어 메타데이터 입력: 이름, 부제, 홍보 문구, 설명, 키워드, 주 카테고리 건강 및 피트니스, 보조 카테고리 생산성, 저작권 | `metadata-ko.md` | 7단계 완료, 저작권 실제값 확정, 현행 Apple 메타데이터·앱 정보 필드 규칙과 한도 재확인 | 출시 책임자 | ☐ 미완료 | 현행 Apple 메타데이터 규칙 재확인과 App Store Connect 한국어 메타데이터 저장 화면. v1의 `What’s New in this Version`은 필드 비가용이므로 입력하지 않음 |
| 9 | 필수 | 개인정보 처리방침·지원·마케팅 페이지를 후속 공개하고, 선정한 이메일 서비스 제공자의 신원·처리 위치·국외 이전·보호조치·보관 사실을 개인정보 처리방침과 지원 페이지에 일관되게 반영한 후 App Store Connect에 Privacy URL과 Support URL을 필수 입력. Marketing URL은 선택적으로 입력하거나 의도적으로 입력하지 않기로 한 결정을 기록 | `privacy-policy-ko.md`, `support-ko.md`, `marketing-ko.md`, `privacy-and-review-ko.md` | 아래 GitHub Pages 공개 게이트 완료 및 선정한 이메일 서비스 제공자 관련 사실 확인 | 공개·규정 책임자 | ☐ 미완료 | 활성 HTTPS 개인정보 처리방침·지원·마케팅 페이지와 상호 링크, 이메일 서비스 제공자의 신원·처리 위치·국외 이전·보호조치·보관 사실이 개인정보 처리방침·지원 페이지에 일관되게 반영된 증거, App Store Connect의 Privacy URL·Support URL 입력, Marketing URL 입력 또는 의도적 미입력 결정 기록 |
| 10 | 필수 | 연령 등급 설문 입력 및 글로벌·대한민국 표시 결과 기록 | `privacy-and-review-ko.md` | 실제 App Store Connect 설문 화면 | 규정 책임자 | ☐ 미완료 | Health or Wellness Topics 답변과 App Store Connect가 계산한 실제 결과. 문서의 글로벌 9+ 예상과 대한민국 All 예상은 고정 보증이 아님 |
| 11 | 필수 | 수출 규정 결정 트리 완료: 암호화 접근 확인, OS 내부·OS 밖 industry-standard·proprietary/non-standard 분류, 면제·문서 업로드 필요 여부 판단, `ITSAppUsesNonExemptEncryption` 값 확인 | `privacy-and-review-ko.md` | 실제 최종 빌드와 통합 라이브러리 검토 | 규정·빌드 책임자 | ☐ 미완료 | 수출 규정 판단 기록, 필요한 문서, 실제 제출 설정 값 |
| 12 | 필수 | iPhone 6.9형과 13형 iPad 스크린샷을 각각 5장 업로드 | `screenshots-ko.md` | 최종 빌드 기기별 직접 캡처, 권리 증빙, 현행 Apple 스크린샷 규격 재확인, native 픽셀·무리사이즈·포맷·alpha·비식별 데이터·4+ 적합 콘텐츠 검수 | 시각 자료 책임자 | ☐ 미완료 | 현행 Apple 스크린샷 규격 재확인 및 iPhone 1320×2868 5장과 iPad 2064×2752 5장, 총 10개 자산의 4+ 적합 콘텐츠 검수를 포함한 업로드 확인 |
| 13 | 필수 | App Review 담당자 연락처와 Review Notes 입력, 지원되는 실제 iPad의 WeatherKit attribution 흐름 녹화 첨부 | `privacy-and-review-ko.md` | 실제 연락처 확정, Review Notes 붙여넣기 원문이 UTF-8 4,000 bytes 이하인지 확인, `MORU-1.0-6-WeatherKit-Attribution.mov` 실기기 녹화 완료 | 심사 책임자 | ☐ 미완료 | 담당자명·이메일·전화번호, 실기기 녹화 첨부, Review Notes 저장 화면 필요. 현재 원문은 985 UTF-8 bytes. 녹화 첨부 전에는 첨부 완료 문구를 사용하지 않음 |
| 14 | 필수 | 최종 제출 확인 | 이 체크리스트 및 모든 출시 자료 | 1~13단계의 필수·적용 조건부 항목 완료 | 출시 책임자 | ☐ 미완료 | 제출 전 검토 기록과 App Store Connect 제출 확인 |

## GitHub Pages 후속 공개 게이트

9단계는 아래 순서를 모두 충족하기 전까지 완료로 표시하지 않습니다.

1. 아래 11개 토큰을 실제 값으로 교체합니다.
2. 선정한 이메일 서비스 제공자의 신원, 처리 위치·국외 이전, 보호조치, 보관 관련 사실을 확인하고 개인정보 처리방침과 지원 페이지에 일관되게 반영합니다.
3. 개인정보 처리방침, 지원, 마케팅 페이지를 공개합니다.
4. 각 공개 페이지가 HTTPS로 2xx 응답을 반환하는지 확인합니다.
5. 모바일 가독성과 페이지 간 상호 링크를 확인합니다.
6. Support URL이 실제 연락 수단과 계정·현지 법상 요구되는 연락 정보를 충족하는지 확인합니다.
7. 그 뒤에만 App Store Connect에 Privacy URL과 Support URL을 입력하고, Marketing URL은 선택적으로 입력하거나 의도적 미입력 결정을 기록합니다.

## 11개 토큰 교체 인덱스

| 토큰 | 사용 문서 | 교체 책임 | 완료 증거 |
|---|---|---|---|
| [확정 필요: 운영자 법적명] | `privacy-policy-ko.md` | 운영·법무 책임자 | 공개 정책에 실제 법적 운영자명이 반영됨 |
| [확정 필요: 지원 이메일] | `support-ko.md` | 지원 책임자 | 수신 가능한 실제 지원 연락 수단 확인 |
| [확정 필요: 개인정보 문의 이메일] | `privacy-policy-ko.md`, `support-ko.md` | 개인정보 책임자 | 수신 가능한 실제 개인정보 문의 연락 수단 확인 |
| [확정 필요: App Review 담당자명] | `privacy-and-review-ko.md` | 심사 책임자 | App Store Connect 심사 연락처에 실제 담당자명 입력 |
| [확정 필요: App Review 이메일] | `privacy-and-review-ko.md` | 심사 책임자 | App Store Connect 심사 연락처에 실제 이메일 입력 |
| [확정 필요: App Review 전화번호] | `privacy-and-review-ko.md` | 심사 책임자 | App Store Connect 심사 연락처에 실제 전화번호 입력 |
| [확정 필요: 저작권자] | `metadata-ko.md` | 권리 책임자 | 권리 증빙과 App Store Connect 저작권 필드 일치 |
| [확정 필요: 최초 공개 연도] | `metadata-ko.md` | 출시 책임자 | 실제 최초 공개 연도와 App Store Connect 저작권 필드 일치 |
| [후속 공개: 개인정보 처리방침 URL] | `support-ko.md`, `marketing-ko.md` | 공개·개인정보 책임자 | 활성 HTTPS 개인정보 처리방침 URL과 Privacy URL 입력 확인 |
| [후속 공개: 지원 URL] | `marketing-ko.md` | 공개·지원 책임자 | 활성 HTTPS 지원 URL과 실제 연락 수단 확인 |
| [후속 공개: 마케팅 URL] | `marketing-ko.md` | 공개 책임자 | 활성 HTTPS 마케팅 페이지 URL과 App Store Connect Marketing URL 입력 또는 의도적 미입력 결정 기록 |

모든 토큰의 실제값 교체, 공개, 입력, 업로드, 제출은 미래 작업이며 현재 상태는 미완료입니다.
