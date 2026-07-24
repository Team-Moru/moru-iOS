# 모루 공용 컴포넌트 사용표

이 문서는 화면을 만들 때 어떤 공용 컴포넌트를 쓰면 되는지 정리한 문서입니다.

이미지로 보고 싶으면 먼저 아래 문서를 보면 됩니다.

- `docs/CommonComponentsPreview.md`

## 기본 규칙

화면을 만들 때는 아래 순서로 확인합니다.

1. `CommonComponentsPreview.md`에서 비슷한 UI를 찾습니다.
2. 있으면 공용 컴포넌트를 가져다 씁니다.
3. 없으면 feature 안에 따로 만듭니다.
4. 같은 UI가 여러 화면에서 반복되면 공용 컴포넌트로 옮깁니다.

색상, 폰트, 간격, radius는 직접 만들지 말고 아래 값을 사용합니다.

```swift
AppColor
AppFont
AppSpacing
AppRadius
```

Figma 세부 보정 파일럿에서는 기존 화면을 전역 변경하지 않고
opt-in API를 사용합니다.
사용법과 캡처·비교 기준은 `docs/FigmaPilotFoundation.md`를 참고합니다.

## 현재 공용 컴포넌트

| SwiftUI 이름 | 주로 쓰는 곳 |
| --- | --- |
| `MoruButton` | 다음, 저장, 시작하기 같은 주요 버튼 |
| `MoruBottomCTA` | 화면 하단에 고정되는 버튼 영역 |
| `MoruCard` | 흰색 카드 박스 |
| `MoruChip` | 키워드, 태그, 선택지 |
| `MoruToggle` | on/off 설정 |
| `MoruProgressBar` | 온보딩 단계, 루틴 진행 단계 |
| `MoruWeekdaySelector` | 알람 반복 요일 선택 |
| `MoruTabBar` | 홈 / 루틴 / 이력 / 마이 탭 |
| `MoruCheckBadge` | 완료, 진행중 같은 상태 표시 |
| `MoruSelectControl` | 플러스 / 마이너스 버튼 |
| `MoruSelectionCard` | 온보딩 선택 카드 |
| `MoruRoutineCard` | 루틴 목록 카드 |
| `MoruRoutineStepRow` | 루틴 항목 row |
| `MoruVoiceCard` | 음성 선택 카드 |
| `MoruTimeSettingCard` | 알람 시간 표시 카드 |
| `MoruTimerStatus` | 남은 시간 표시 |
| `MoruSoundModule` | 음성 안내 / 사운드 상태 |
| `MoruRecordingStatus` | 녹음 상태 |
| `MoruDialog` | 확인 팝업 |

## 화면별로 먼저 볼 컴포넌트

| 화면 | 먼저 볼 공용 컴포넌트 |
| --- | --- |
| 온보딩 | `MoruProgressBar`, `MoruSelectionCard`, `MoruButton`, `MoruBottomCTA` |
| 루틴 설정 | `MoruRoutineCard`, `MoruRoutineStepRow`, `MoruSelectControl`, `MoruButton` |
| 알람 설정 | `MoruTimeSettingCard`, `MoruWeekdaySelector`, `MoruToggle`, `MoruButton` |
| 루틴 실행 | `MoruProgressBar`, `MoruTimerStatus`, `MoruSoundModule`, `MoruRecordingStatus`, `MoruDialog` |
| 홈 | `MoruRoutineCard`, `MoruCard`, `MoruButton` |
| 이력 | `MoruCard`, `MoruCheckBadge`, `MoruRoutineStepRow` |
| 마이 / 설정 | `MoruToggle`, `MoruVoiceCard`, `MoruButton`, `MoruCard` |

## 사용 예시

```swift
MoruButton("루틴 시작하기") {
  viewModel.startRoutine()
}
```

```swift
MoruRoutineCard(
  title: "활력 루틴",
  description: "6개 항목 · 15분",
  isActive: true
)
```

```swift
MoruRoutineStepRow(
  index: 1,
  title: "잠자리 정리하기",
  subtitle: "확인형 - 1분",
  isCompleted: false
)
```

## v1.0에서 조심할 것

v1.0은 서버 없이 로컬에서 돌아가는 앱입니다.

그래서 아래 UI는 지금은 만들지 않거나 문구를 바꿉니다.

| Figma에 있는 표현 | v1.0에서는 |
| --- | --- |
| 소셜 로그인 | 나중에 추가 |
| PRO / 결제 화면 | 나중에 추가 |
| AI 분석 | 루틴 정리 / 추천 루틴 |
| AI 음성 안내 | 음성 안내 |
| 회원 탈퇴 | 로컬 데이터 초기화 |

## 코드 위치

공용 컴포넌트 코드는 여기 있습니다.

```text
Moru/DesignSystem/Components
```

디자인 토큰은 여기 있습니다.

```text
Moru/DesignSystem/Tokens
```

폴더 구조는 이렇게 보면 됩니다.

```text
Moru/DesignSystem
├─ Tokens
│  ├─ AppColor.swift
│  ├─ AppFont.swift
│  ├─ AppIcon.swift
│  └─ AppLayout.swift
├─ Components
│  ├─ MoruButton.swift
│  ├─ MoruCard.swift
│  ├─ MoruChip.swift
│  └─ ...
└─ Preview
   └─ DesignSystemPreview.swift
```
