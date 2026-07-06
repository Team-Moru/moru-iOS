# 🚀 프로젝트 이름

![배너 이미지 또는 로고](링크)

# 🌅 MORU (모루) - 모닝 루틴 알람 서비스
> **"매일 아침, 당신의 가장 평온하고 활기찬 시작을 돕는 모닝 루틴 알람 앱"**
> 모루(MORU)는 모닝 루틴의 줄임말로, 사용자가 아침에 눈을 떠서 기분 좋은 루틴을 완수할 수 있도록 돕는 음성 코칭 기반 알람 어플리케이션입니다.

[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)]()
[![Xcode](https://img.shields.io/badge/Xcode-26.3+-blue.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)]()

---

<br>

## 👥 멤버
| **초이** | **찬혁** | **레티** | **개미** |

모루 iOS 팀은 화면 단위 분배보다 **"공통 기준 정의 및 책임 책임제"**를 통해 AI 툴 활용 시 발생할 수 있는 코드 파편화를 방지합니다.

| 이름 | 역할 및 담당 영역 |
| :--- | :--- |
| **초이** | Foundation/SwiftData + 온보딩(첫 루틴 생성 및 알람 설정 후 SwiftData에 저장) 구현 |
| **개미** | 루틴 실행 및 완료 UI + Local TTS 음성 안내 + Speech Input 구현 |
| **찬혁** | Home/Routine 탭에 해당하는 UI 구현  |
| **레티** | 이력 + 프로필 + 설정 UI 구현 |

<br>


## 📱 소개

> 단순한 알람 해제를 넘어 기상 직후 루틴 수행을 돕는 코칭 중심 서비스. 화면 터치 없이 음성(STT)과 가이드(TTS)를 통해 자연스럽게 아침 루틴을 진행하도록 유도합니다.

<br>

## 📆 프로젝트 기간
- 전체 기간: `2026.06.23 - YYYY.MM.DD`
- 개발 기간: `2026.07.02 - YYYY.MM.DD`

<br>

## 🤔 요구사항
For building and running the application you need:

iOS 26.0 <br>
Xcode 26.3+ <br>
Swift 6.2

<br>

## ⚒️ 개발 환경
* Front : SwiftUI
* 버전 및 이슈 관리 : Github, Github Issues
* 협업 툴 : Discord, Notion

<br>

## 🔎 기술 스택
### Envrionment
<div align="left">
<img src="https://img.shields.io/badge/git-%23F05033.svg?style=for-the-badge&logo=git&logoColor=white" />
<img src="https://img.shields.io/badge/github-%23121011.svg?style=for-the-badge&logo=github&logoColor=white" />
<img src="https://img.shields.io/badge/SPM-FA7343?style=for-the-badge&logo=swift&logoColor=white" />
</div>

### Development
<div align="left">
<img src="https://img.shields.io/badge/Xcode-007ACC?style=for-the-badge&logo=Xcode&logoColor=white" />
<img src="https://img.shields.io/badge/SwiftUI-42A5F5?style=for-the-badge&logo=swift&logoColor=white" />
<img src="https://img.shields.io/badge/Alamofire-FF5722?style=for-the-badge&logo=swift&logoColor=white" />
<img src="https://img.shields.io/badge/Moya-8A4182?style=for-the-badge&logo=swift&logoColor=white" />
<img src="https://img.shields.io/badge/Kingfisher-0F92F3?style=for-the-badge&logo=swift&logoColor=white" />
<img src="https://img.shields.io/badge/Combine-FF2D55?style=for-the-badge&logo=apple&logoColor=white" />
</div>

### Communication
<div align="left">
<img src="https://img.shields.io/badge/Notion-white.svg?style=for-the-badge&logo=Notion&logoColor=000000" />
<img src="https://img.shields.io/badge/Discord-5865F2?style=for-the-badge&logo=Discord&logoColor=white" />
<img src="https://img.shields.io/badge/Figma-F24E1E?style=for-the-badge&logo=figma&logoColor=white" />
</div>

<br>

## 📱 화면 구성
<table>
  <tr>
    <td>
      사진 넣어주세요
    </td>
    <td>
      사진 넣어주세요
    </td>
   
  </tr>
</table>

## 🔖 브랜치 컨벤션
속도감 있는 개발과 유연한 통합을 위해 **`main` 브랜치 중심 개발** 전략을 채택합니다. 데모 직전에만 안정화 브랜치를 분기합니다.

### Git-Flow 학습 및 팀 적용 방식

MORU iOS 팀은 Git-Flow의 핵심 개념인 **역할별 브랜치 분리와 PR 기반 병합**을 참고하되, 현재 프로젝트 규모와 일정에 맞게 단순화해서 적용합니다.

- `main`은 항상 빌드 및 실행 가능한 최신 상태를 유지합니다.
- 기능 개발, 버그 수정, 문서 작업은 각각 목적에 맞는 브랜치에서 진행합니다.
- 작업 완료 후 Pull Request를 생성하고, 팀원 리뷰를 거친 뒤 `main`에 병합합니다.
- 실험성 작업은 `spike/*` 브랜치에서 검증하고, 실제 반영이 필요하면 `feat/*` 브랜치에서 정리해 구현합니다.

### 작업 흐름

1. 작업할 내용을 GitHub Issue로 기록합니다.
2. 작업 성격에 맞는 브랜치를 생성합니다.
3. 기능 구현 또는 문서 작업을 진행합니다.
4. 로컬에서 빌드 또는 Preview를 확인합니다.
5. 원격 브랜치에 push 후 Pull Request를 생성합니다.
6. 리뷰를 반영한 뒤 `main`에 merge합니다.

### 📌 브랜치 명명 규칙 (Branch Naming)
- **`main`** : 항상 빌드 및 실행 가능한 최신 상태 유지 (PR 리뷰 후 병합)
- **`feat/#이슈번호-작업명`** : 새로운 기능 및 화면 개발 (예: `feat/#12-onboarding`)
- **`fix/#이슈번호-작업명`** : 버그 수정 (예: `fix/#21-nav-bug`)
- **`chore/#이슈번호-작업명`** : 설정, 구조, 문서, 패키지 작업 (예: `chore/#8-setup`)
- **`spike/#이슈번호-작업명`** : 기술 가능성 검증 및 R&D (예: `spike/#16-alarm-tts`)
- **`release/demo-2026-08`** : 데모 직전 생성하는 안정화 브랜치 (버그 수정 위주)

<br>

## 🌀 코딩 컨벤션

### 1. 레이아웃 및 포맷팅 (Layout & Formatting)
- **들여쓰기:** 탭(tab) 대신 **2개의 Space**를 사용합니다.
- **최대 줄 길이:** 한 줄은 최대 **99자**를 넘지 않도록 합니다. (Xcode 설정 권장)
- **콜론(`:`):** 콜론의 오른쪽에만 공백을 둡니다. (`let names: [String: String]?`)
- **빈 줄 관리:** 빈 줄에는 공백이 포함되지 않아야 하며, 모든 파일은 빈 줄로 끝납니다.
- **임포트(Import):** 알파벳 순으로 정렬하며, 내장 프레임워크 ➔ (빈 줄) ➔ 서드파티 순으로 작성합니다.

### 2. 줄바꿈 규칙 (Line Breaks)
함수나 호출 코드가 최대 길이를 초과할 경우 파라미터 기준으로 줄바꿈합니다. (클로저가 2개 이상이면 무조건 내려씁니다.)

```swift
// ✅ 좋은 예: 함수 호출 줄바꿈
let actionSheet = UIActionSheet(
  title: "정말 계정을 삭제하실 건가요?",
  delegate: self,
  cancelButtonTitle: "취소",
  destructiveButtonTitle: "삭제해주세요"
)

// ✅ 좋은 예: if let / guard let 줄바꿈 및 들여쓰기
guard let user = self.veryLongFunctionNameWhichReturnsOptionalUser(),
      let name = user.veryLongFunctionNameWhichReturnsOptionalName(),
      user.gender == .female else {
  return
}
```

### 3. 네이밍 원칙 (Naming Rules)
- **UpperCamelCase:** 클래스, 구조체, 열거형(Enum), 프로토콜 (접두사 사용 금지)
- **lowerCamelCase:** 함수, 변수, 상수, Enum case
- **약어:** 시작할 때는 소문자, 그 외에는 대문자 (`userID`, `html`, `websiteURL`)
- **Action 함수:** `주어 + 동사 + 목적어` 형태 사용 (`backButtonDidTap()`)
  - *Tap*(눌렀다 뗌), *Press*(누름), *will~*(직전), *did~*(직후), *should~*(Bool 반환)

```swift
// ✅ 좋은 예
class ProfileView: UIView { ... }
func backButtonDidTap() { ... }
let maximumNumberOfLines = 3
enum Result { case success, failure }

// ❌ 나쁜 예
class profileView: UIView { ... } // 소문자 시작
func back() { ... } // 동사 불명확
let MAX_LINES = 3 // 스네이크 케이스
enum Result { case Success } // Case에 대문자 시작
```

### 3.4. 클로저 (Closures)
- 파라미터와 리턴이 없는 경우 `() -> Void` 사용
- 괄호 생략 및 가능하면 타입 정의 생략
- 유일한 마지막 파라미터 클로저인 경우 파라미터 이름 생략(Trailing Closure)

```swift
// ✅ 좋은 예
UIView.animate(withDuration: 0.5) {
  // doSomething()
}

// ❌ 나쁜 예
UIView.animate(withDuration: 0.5, animations: { () -> Void in
  // doSomething()
})
```

### 3.5. 뷰 및 컴포넌트 개발 권장사항 (Best Practices)

**1) 프로토콜 채택은 Extension으로 분리합니다.**
```swift
final class MyViewController: UIViewController { ... }

// MARK: - UITableViewDataSource
extension MyViewController: UITableViewDataSource { ... }
```

**2) Then 라이브러리 스타일로 선언과 동시에 초기화합니다.**
```swift
let nameLabel = UILabel().then {
  $0.textAlignment = .center
  $0.textColor = .black
}
```

**3) UI 상수는 Enum으로 묶어 네임스페이스를 활용합니다.**
```swift
final class ProfileViewController: UIViewController {
  private enum Metric {
    static let profileImageViewLeft = 10.0
    static let nameLabelTopBottom = 8.0
  }
  
  private enum Font {
    static let nameLabel = AppFont.bold14 // DesignSystem 활용
  }
  
  // 사용 시
  // self.nameLabel.font = Font.nameLabel
}
```

**4) 타입 선언 시 단축 문법을 사용합니다.**
```swift
var messages: [String]?       // ✅ 좋은 예
var messages: Array<String>?  // ❌ 나쁜 예
```

**5) 주석 (Comments)**
- 문서화 주석은 `///` 를 사용합니다.
- 영역 구분은 `// MARK: - 이름` 을 사용하며, 위아래로 공백을 둡니다.

<br>

## 📁 PR 컨벤션
* PR 시, 템플릿이 등장한다. 해당 템플릿에서 작성해야할 부분은 아래와 같다
    1. `PR 유형 작성`, 어떤 변경 사항이 있었는지 [] 괄호 사이에 x를 입력하여 체크할 수 있도록 한다.
    2. `작업 내용 작성`, 작업 내용에 대해 자세하게 작성을 한다.
    3. `추후 진행할 작업`, PR 이후 작업할 내용에 대해 작성한다
    4. `리뷰 포인트`, 본인 PR에서 꼭 확인해야 할 부분을 작성한다.
    6. `PR 태그 종류`, PR 제목의 태그는 아래 형식을 따른다.

#### 🌟 태그 종류 (커밋 컨벤션과 동일)

| 태그 | 설명 |
| --- | --- |
| `[Feat]` | 새로운 기능 또는 화면 구현 |
| `[Fix]` | 버그 수정 |
| `[Design]` | UI 디자인, 스타일, 레이아웃 변경 |
| `[Refactor]` | 동작 변경 없는 코드 구조 개선 |
| `[Docs]` | README, 문서 수정 |
| `[Chore]` | 설정, 빌드, 파일 정리 등 기타 작업 |
| `[Test]` | 테스트 코드 추가 및 수정 |

### ✅ PR 예시 모음
>  [Chore] 프로젝트 초기 세팅 <br>
>  [Feat] 프로필 화면 UI 구현 <br>
>  [Fix] iOS 26에서 버튼 클릭 오류 수정 <br>
>  [Design] 로그인 화면 레이아웃 조정 <br>
>  [Docs] README에 프로젝트 소개 추가 <br>

<br>

## 📑 커밋 컨벤션
### 🏷️ 커밋 태그 가이드

커밋 메시지는 아래 형식을 사용합니다.

```text
[태그] 작업 내용
```

예시:

```text
[Feat] 홈 화면 UI 구현
[Fix] 디자인 토큰 중복 선언 제거
[Refactor] 공용 컴포넌트 파일 구조 정리
[Docs] README 컨벤션 추가
```

| 태그 | 설명 |
| --- | --- |
| `[Feat]` | 새로운 기능 또는 화면 구현 |
| `[Fix]` | 버그 수정 |
| `[Design]` | UI 디자인, 스타일, 레이아웃 변경 |
| `[Refactor]` | 동작 변경 없는 코드 구조 개선 |
| `[Docs]` | 문서 추가 및 수정 |
| `[Chore]` | 설정, 빌드, 파일 정리 등 기타 작업 |
| `[Test]` | 테스트 코드 추가 및 수정 |

### ✅ 커밋 예시 모음
>  [Chore] 프로젝트 초기 세팅 <br>
>  [Feat] 프로필 화면 UI 구현 <br>
>  [Fix] iOS 26에서 버튼 클릭 오류 수정 <br>
>  [Design] 로그인 화면 레이아웃 조정 <br>
>  [Docs] README에 프로젝트 소개 추가 <br>

<br>

## 🗂️ 폴더 컨벤션
프로젝트 구조는 MVVM 아키텍처와 도메인(기능) 중심으로 분리하여 관리합니다.

```text
Moru
├─ App
│  ├─ MoruApp.swift
│  ├─ AppRouter.swift            // 기본 flow: local session (auth 아님)
│  ├─ DependencyContainer.swift  // .local(modelContext:) 기본, .mock()은 #if DEBUG
│  └─ SessionStore.swift         // LocalProfile + onboarding 상태
├─ DesignSystem
│  ├─ MoruDesignTokens.swift     // 색/간격/radius — Figma variables와 매핑
│  ├─ Fonts.swift                // Pretendard 스타일 (D10)
│  └─ Components/                // Figma '컴포넌트' 섹션(1445:1113) 기준
├─ Domain
│  ├─ Models/                    // Routine, RoutineStep, AlarmSchedule, RoutineRun, RoutineStepResult, LocalProfile, SyncMetadata
│  ├─ UseCases/
│  ├─ Repositories/              // RoutineRepository, RoutineRunRepository, LocalProfileRepository
│  └─ Services/                  // RoutineSuggestionService (D5)
├─ Data
│  ├─ Persistence/               // MoruSchemaV1, SchemaMigrationPlan (D3)
│  ├─ Local/                     // SwiftData repositories + Mappers
│  └─ Mock/                      // Preview/Snapshot/QA/Test 전용
├─ Platform
│  ├─ Alarm/                     // AlarmKit + LocalNotification fallback
│  ├─ TTS/                       // LocalTTSService
│  └─ Speech/
├─ Debug/                        // DeviceQA 패널/레코더 (ContentView에서 분리, #if DEBUG)
└─ Features
   ├─ Onboarding
   ├─ Home            // 홈 대시보드
   ├─ RoutineList     // 루틴 목록/수정/삭제
   ├─ RoutineCreate   // 직접 만들기 + 제안 받기
   ├─ AlarmSetting
   ├─ RoutinePlayer   // 스텝 실행 (확인/타이머/입력)
   ├─ History         // 이력/주간 리포트/일별 기록
   └─ Profile         // 설정
```

### Foundation / SwiftData v1 기준
- v1 저장 정책은 **localOnly + hard delete**입니다.
- `RoutineRepository.deleteRoutine(id:)`는 Routine을 실제 삭제합니다.
- Routine 삭제 시 step/alarm은 SwiftData cascade로 삭제하고, `RoutineRun` 기록은 유지합니다.
- soft delete를 뜻하는 `deletedAt`, `includeDeleted`, `pendingDelete` 계약은 v1에서 사용하지 않습니다.
- Feature View/ViewModel은 `SwiftData`, `@Query`, `ModelContext`를 직접 사용하지 않습니다.
- 화면 계층은 `DependencyContainer`가 제공하는 Repository/Service 계약만 사용합니다.
- SwiftData 접근은 `Data/Persistence`, `Data/Local`, App bootstrap, 테스트로 제한합니다.
- 앱 루트는 `.modelContainer(...)`를 전역 주입하지 않습니다.
