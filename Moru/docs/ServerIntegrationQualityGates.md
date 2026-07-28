# Server Integration Quality Gates

이 문서는 계정, 서버 음성, 서버 루틴 추천 연동에서 CI가 고정하는 아키텍처와 개인정보 경계를 설명한다. 서버 요청 필드나 저장 방식이 바뀌면 구현과 함께 이 문서, 개인정보 manifest, audit allowlist를 다시 검토해야 한다.

## Dependency direction

`Domain`은 유스케이스, 모델, 저장소·서비스 포트와 도메인 오류를 소유한다. `App`, `Data`, `Network`는 그 포트를 조립하거나 구현하고 외부 오류를 도메인 오류로 변환한다.

`Scripts/check-domain-dependency-boundary.sh`는 다음 역방향 의존을 차단한다.

- `Domain`의 SwiftUI, SwiftData, Moya, Alamofire 및 로그인 provider SDK import
- `App`, `Data`, `Network`에서 선언한 타입을 `Domain`이 직접 참조하는 코드

새 서버 기능은 먼저 `Domain`에 최소 포트를 정의하고, 구체 API client, DTO, target, session store는 바깥 계층에서 연결한다.

## Reviewed data flow

현재 서버 전송 범위는 다음과 같다.

| 흐름 | 서버로 전송하는 값 | 서버로 보내지 않는 관련 값 |
| --- | --- | --- |
| 소셜 로그인 | provider token, 선택적 authorization code | Apple 이름·이메일 scope |
| 토큰 갱신·로그아웃 | refresh token | 로컬 프로필과 루틴 데이터 |
| 루틴 추천 | `goalTags`, `selectedKeywords`, `freeformText`를 합친 최대 200자 `userInput` | 기상 시간, 요일, 루틴 이름, 알람, 음성, transcript, 위치, 날씨, 건강 데이터 |
| 서버 음성 선택 | `ttsId` | 로컬 음성 ID, 로컬 루틴·실행 기록 |

계정 credential은 `AfterFirstUnlockThisDeviceOnly` Keychain에 저장하고 iCloud Keychain 동기화를 사용하지 않는다. 계정별 음성 cache와 전송 대기 mutation은 SwiftData에 저장하지만, 네트워크 logger는 HTTP method, path, status만 기록하고 header, token, request·response body는 기록하지 않는다.

계정에 귀속되는 음성·AI 요청은 `memberID`와 account session generation을 bearer token과 함께 고정한다. 요청 도중 로그아웃·재로그인 또는 계정 전환이 발생하면 성공 응답과 실패 응답을 모두 폐기한다. 로그아웃·회원 탈퇴는 해당 계정의 동기화 admission을 닫고 in-flight 작업을 취소·drain하며, 로그인 성공 또는 session 복원 때만 다시 열고 Outbox를 동기화한다.

`PrivacyInfo.xcprivacy`는 이 범위에 맞춰 연결된 사용자 ID, AI 입력에 해당하는 기타 사용자 콘텐츠, 서버 음성 선택에 해당하는 제품 상호작용을 선언한다. 추적은 사용하지 않는다. 앱 내부 상태를 저장하는 UserDefaults에는 `CA92.1` required reason을 선언한다.

## Pull request checks

`Foundation Checks` workflow는 모든 pull request에서 다음을 실행한다.

1. 기존 iPhone 기능, SwiftData, 소셜 로그인 설정 shell gate
2. Domain dependency boundary와 서버 연동 개인정보 audit
3. macOS 26 runner의 Xcode 26.5에서 고정된 `Package.resolved` 해석
4. generic iOS 대상으로 Debug와 Release build
5. iOS 26.5 iPhone 17 Pro simulator에서 비visual 전체 test를 blocking gate로 실행
6. 같은 simulator에서 visual test partition을 별도 nonblocking job으로 실행하고 항상 xcresult를 보관

로컬 정적 검증 명령은 다음과 같다.

```sh
bash Scripts/check-iphone-functional-gate.sh
bash Scripts/check-swiftdata-boundary.sh
bash Scripts/check-social-login-release-config.sh
bash Scripts/check-domain-dependency-boundary.sh
bash Scripts/audit-server-integration-privacy.sh
```

로컬 Xcode 검증은 CI와 동일하게 `Moru/Moru.xcodeproj`, `Moru` scheme, Xcode 26.5를 사용한다.

## Visual baseline debt

변경 전 `origin/main`을 Xcode 26.5와 iPhone 17 Pro simulator에서 실행한 기준으로, 전체 402개 test 중 visual test method 7개에 걸친 perceptual-hash assertion 69개가 이미 drift 상태다. 이 기존 실패 때문에 새 서버 연동 PR이 항상 red가 되지 않도록 비visual test는 blocking, visual partition은 관측 가능한 nonblocking job으로 분리한다.

visual job도 모든 pull request에서 실행되고 xcresult를 남긴다. 기준 이미지를 승인·갱신해 drift를 해소한 뒤에는 `continue-on-error`를 제거해 blocking gate로 승격해야 한다. visual 실패를 기능 회귀와 무관하다고 자동 간주하거나 test 자체를 제외하는 용도로 이 partition을 확장하지 않는다.
