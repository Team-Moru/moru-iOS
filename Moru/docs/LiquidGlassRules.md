# Liquid Glass를 어디에 쓰고 어디에 쓰지 않는가

카드를 전부 유리로 바꿨다가 되돌린 기록이다. 같은 실수를 반복하지 않기 위해 남긴다.

## 무엇이 문제였나

2026-09-12에 앱 전체 카드 표면을 `glassEffect`로 바꿨다. 배경과 겉돌았고,
배경에 깊이를 주는 것으로 보정하려 했지만 나아지지 않았다.

원인은 배경이 아니라 **계층**이었다.

## 규칙

### 1. 유리는 콘텐츠 위에 떠 있는 것에만

탭바·툴바·시트·팝오버·버튼처럼 **조작하는 것**이 유리다.
목록·표·카드·미디어는 **읽는 것**이고 유리가 아니다.

> "Liquid Glass is exclusively for the navigation layer that floats above app content.
> Never apply to content itself (lists, tables, media)."

이 선을 넘으면 무엇이 누를 수 있는 것이고 무엇이 내용인지 구별이 무너진다.

### 2. 유리 위에 유리를 올리지 않는다

유리는 다른 유리를 샘플링하지 못한다. 겹치면 굴절 대신 얼룩이 생긴다.

> "Glass cannot sample other glass; container provides shared sampling region."

한 화면에 유리 요소가 여럿이면 `GlassEffectContainer`로 묶어 샘플링 영역을 공유시킨다.

### 3. 틴트는 의미를 담을 때만

주요 동작, 선택 상태처럼 말할 것이 있을 때 색을 얹는다.

> "Convey semantic meaning (primary action, state), NOT decoration."

카드마다 색을 주면 그 색이 아무 뜻도 갖지 못한다.

### 4. 유리 뒤에는 볼 것이 있어야 한다

가장 투명한 `.clear`는 세 조건을 **동시에** 만족할 때만 쓴다 — 뒤가 사진·영상처럼
풍부하고, 어두워져도 상관없고, 유리 위 글자가 굵고 밝을 것. 보통은 `.regular`.

### 5. 투명도 줄이기는 시스템에 맡긴다

사용자가 켜면 유리가 스스로 불투명해진다. 직접 덮어쓰지 않는다.

## 세 원칙 (WWDC)

| 원칙 | 뜻 | 모루에서 |
| --- | --- | --- |
| Hierarchy | 컨트롤이 아래 콘텐츠를 들어 올려 구별되게 한다 | 유리는 위에 뜬 것만. 카드는 바닥에 붙어 있다 |
| Harmony | 하드웨어의 동심원 형태와 소프트웨어가 맞물린다 | 모서리 반경을 기기 곡률과 맞춘다 |
| Consistency | 화면이 아니라 체계를 만든다. 장식이 아니라 목적으로 | 유리·간격·모션은 깊이나 맥락 전환을 알릴 때만 |

## 모루의 현재 배치

**유리 (컨트롤 계층)**

| 위치 | 무엇 |
| --- | --- |
| `MoruButton` | `.glassProminent`(주요) / `.glass`(보조) |
| `MainTabView` | 네이티브 탭바 — 시스템이 그린다 |
| `AlarmRingView` | 다시 알림 버튼 |
| `AlarmRoutineCardView` | 알람 화면의 루틴 카드 — 전체화면 그라데이션 위라 예외로 둔다 |

**불투명 (콘텐츠 계층)**

`MoruCard`. 표면 색은 **시스템 시맨틱 색**이다.

| 토큰 | 값 |
| --- | --- |
| `MoruColor.canvas` | `systemGroupedBackground` |
| `MoruColor.cardSurface` | `secondarySystemGroupedBackground` |
| `MoruColor.tileSurface` | `tertiarySystemFill` |

명도 관계를 우리가 정하지 않고 애플이 정한 것을 받는다. 이게 핵심이다 — 시스템이
그리는 탭바 유리는 시스템 위계를 기준으로 자기를 그리는데, 우리가 표면 관계를
직접 발명하면 두 규칙이 어긋나 유리가 겉돈다.

덤으로 프로필 카드가 배경과 **255 중 2**밖에 차이나지 않던 문제가 구조적으로
사라졌다. 테두리도 필요 없다 — 시스템 위계가 이미 카드를 세운다.

상태나 강조를 나타낼 때만 `tint`를 넘긴다(활성 루틴의 주황, 주간 요약의 주황).

표면 색은 hex로 고정하지 않는다. 시스템이 값을 정하고 iOS 버전·외관에 따라
달라지기 때문이다. 대신 `testSurfaceHierarchyKeepsCardsAboveTheCanvas`가
"카드가 바탕보다 충분히 밝다"는 **위계**를 지킨다.

**배경**

`MoruCanvasBackground` — 시스템 바탕만. 한동안 그라데이션 + 브랜드 글로우를
깔았지만 걷었다. 시스템 위계 안에서는 바탕이 조용해야 카드가 선다.

홈은 예외다. 자체 그라데이션과 인사말 뒤 글로우를 유지한다 — 앱의 얼굴이고,
브랜드가 드러나야 할 유일한 화면이다.

**유리 컨트롤의 윤곽**

`MoruButton`은 유리 위에 `Capsule().stroke(...)`를 덧댄다. 없으면 배경이 밝을 때
버튼 경계가 녹아 어디까지 누를 수 있는지 흐려진다. Feedback Buffer도 유리 3곳
모두에서 같은 처리를 한다.

## 출처

- [conorluddy/LiquidGlassReference](https://github.com/conorluddy/LiquidGlassReference) — 애플 HIG 정리
- [Create with Swift — Hierarchy, Harmony, Consistency](https://www.createwithswift.com/liquid-glass-redefining-design-through-hierarchy-harmony-and-consistency/)
- [Apple HIG — Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

인용문은 위 정리 문서의 것이다. 애플 원문 페이지는 자바스크립트로 본문을 그려
직접 인용하지 못했다.
