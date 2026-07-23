# D0 차이 ledger

## 구조

| 영역 | Before | After |
| --- | --- | --- |
| token | 기존 `App*` token만 사용 | 기존 token을 보존한 `MoruPilot*` opt-in alias |
| typography | size 중심 `AppFont` | D1~C2 size/140% line height의 `MoruTextStyle` |
| 공용 컴포넌트 | 단일 기본 스타일 | `.legacy` 기본값 + 명시적 `.figmaPilot` |
| 캡처 | 테스트별 1× renderer 구현 | 공통 393×852pt, 3× deterministic fixture |
| 비교 | perceptual hash 중심 | side-by-side, 50% overlay, absolute diff, JSON metrics |

## 간격·radius

- 파일럿 spacing: `4/8/10/12/16/20/32/36/64`.
- 파일럿 radius: `16/24/100`.
- routine card 파일럿은 Figma의 20pt inset, 10pt gap, 24pt radius를 사용합니다.
- tab bar 파일럿은 Figma의 95pt Medium chrome을 사용합니다.

## Typography

- D1 `48/67.2`, D2 `36/50.4`.
- H1 `32/44.8`, H2 `28/39.2`, H3 `24/33.6`.
- B1 `22/30.8`, B2 `20/28`, B3 `18/25.2`, B4 `16/22.4`.
- C1 `14/19.6`, C2 `12/16.8`.
- 기본 weight는 display bold, heading semi-bold, body/caption medium입니다.
- `.weight(_:)`로 같은 size/line-height에서 Pretendard weight를 바꿀 수 있습니다.

## 색상

| Alias | Hex |
| --- | --- |
| `canvas` | `#F3F6FC` |
| `accent` | `#FF9861` |
| `accentSoft` | `#FFAC80` |
| `accentTint` | `#FFDFCE` |
| `accentSurface` | `#FFEBE0` |
| `progressTrack` | `#F6F8FA` |
| `border` | `#E3E6EE` |
| `textStrong` | `#3C3D5E` |
| `textPrimary` | `#515574` |
| `textSecondary` | `#80889E` |
| `textTertiary` | `#999FB3` |
| `shadow` | `#D8E3FF` |

## 공용 컴포넌트

- `MoruProgressBar`: accent/label alias와 C2 140% line height.
- `MoruToggle`: 52×28, 20pt thumb, 4pt inset과 파일럿 accent.
- `MoruTabBar`: 70% white material, upward shadow, 95pt Medium chrome.
- `MoruButton`: Figma 349/353×54 Medium 최소 크기와 B4 text style.
- `MoruRoutineCard`: 353×100 Medium geometry, exact tint/shadow, AX3 reflow.

기존 initializer와 `.legacy` 기본 렌더링은 유지됩니다.

## 비교 metric

이번 D0 metric은 같은 component board에서 legacy와 opt-in 파일럿 스타일의
도입 차이를 계측합니다. 따라서 pixel 차이율은 승인 threshold가 아니라
의도된 foundation delta의 크기입니다.

- Medium differing pixels: `19.669994332217033%`.
- AX3 differing pixels: `25.36817360671427%`.
- 동일 After를 재렌더한 비교는 masked/unmasked 영역 모두 `0` diff입니다.
