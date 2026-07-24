# P1 — Splash·온보딩

- Base / Canonical Before: `main@d5104a1c26aa23fcc2a05298e7ebd292ac116fb1`
- Branch: `fix/#66-splash-onboarding-figma-polish`
- Figma file: `RNf4Q84fgsZf3V8MtZmGBc`
- Figma version: `2379679754802507594`
- Issue: [#66](https://github.com/Team-Moru/moru-iOS/issues/66)

## Figma 기준

| 구간 | Nodes |
| --- | --- |
| Splash | `2644:2640`, `2644:2751`, `2644:2797` |
| 경험·목표 | `1445:1309`, `1445:1407` |
| 추천·시간 | `1445:1545`, `1445:1984` |
| 입력·정리 | `1445:2060`, `1445:2189` |
| 검토·알람 | `2389:3811`, `2389:4062`, `1463:2945`, `2092:4936` |
| 음성·완료 | `1463:3389`, `1852:2688`, `1463:3255`, `2092:4288`, `2092:4253` |

18개 원본 PNG는 [`figma/`](figma/)에 저장했다. 긴 scroll frame
`2389:4062`는 동일 viewport 비교를 위해 상단 1179 × 2556 px로 정규화했다.

## 상태별 Before / After

| 상태 | Medium | AX3 |
| --- | --- | --- |
| splash | [Before](states/splash/light-M/before.png) · [After](states/splash/light-M/after.png) | [Before](states/splash/light-AX3/before.png) · [After](states/splash/light-AX3/after.png) |
| experience | [Before](states/experience/light-M/before.png) · [After](states/experience/light-M/after.png) | [Before](states/experience/light-AX3/before.png) · [After](states/experience/light-AX3/after.png) |
| goals | [Before](states/goals/light-M/before.png) · [After](states/goals/light-M/after.png) | [Before](states/goals/light-AX3/before.png) · [After](states/goals/light-AX3/after.png) |
| suggested-routine | [Before](states/suggested-routine/light-M/before.png) · [After](states/suggested-routine/light-M/after.png) | [Before](states/suggested-routine/light-AX3/before.png) · [After](states/suggested-routine/light-AX3/after.png) |
| duration | [Before](states/duration/light-M/before.png) · [After](states/duration/light-M/after.png) | [Before](states/duration/light-AX3/before.png) · [After](states/duration/light-AX3/after.png) |
| freeform | [Before](states/freeform/light-M/before.png) · [After](states/freeform/light-M/after.png) | [Before](states/freeform/light-AX3/before.png) · [After](states/freeform/light-AX3/after.png) |
| organizing | [Before](states/organizing/light-M/before.png) · [After](states/organizing/light-M/after.png) | [Before](states/organizing/light-AX3/before.png) · [After](states/organizing/light-AX3/after.png) |
| review | [Before](states/review/light-M/before.png) · [After](states/review/light-M/after.png) | [Before](states/review/light-AX3/before.png) · [After](states/review/light-AX3/after.png) |
| alarm | [Before](states/alarm/light-M/before.png) · [After](states/alarm/light-M/after.png) | [Before](states/alarm/light-AX3/before.png) · [After](states/alarm/light-AX3/after.png) |
| voice | [Before](states/voice/light-M/before.png) · [After](states/voice/light-M/after.png) | [Before](states/voice/light-AX3/before.png) · [After](states/voice/light-AX3/after.png) |
| completion | [Before](states/completion/light-M/before.png) · [After](states/completion/light-M/after.png) | [Before](states/completion/light-AX3/before.png) · [After](states/completion/light-AX3/after.png) |
| long-korean | [Before](states/long-korean/light-M/before.png) · [After](states/long-korean/light-M/after.png) | [Before](states/long-korean/light-AX3/before.png) · [After](states/long-korean/light-AX3/after.png) |
| preview-unavailable | [Before](states/preview-unavailable/light-M/before.png) · [After](states/preview-unavailable/light-M/after.png) | [Before](states/preview-unavailable/light-AX3/before.png) · [After](states/preview-unavailable/light-AX3/after.png) |

각 variant의 `before-after/`에는 side-by-side, overlay, difference heatmap,
metrics가 있다. 11개 canonical Medium 장면의 `figma-after/`에도 같은 비교
산출물이 있다.

세부 내용은 [delta](delta.md), [exceptions](exceptions.md),
[tests](tests.md), [design QA](design-qa.md)를 참고한다.
