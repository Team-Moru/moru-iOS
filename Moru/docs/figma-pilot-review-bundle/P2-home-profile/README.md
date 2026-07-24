# P2 — Home·Profile

- Base / Canonical Before: `main@02c43e4fb5d2a562659fe702f257350e8b7173e2`
- Branch: `fix/#68-home-profile-figma-polish`
- Figma file: `RNf4Q84fgsZf3V8MtZmGBc`
- Figma version: `2379679754802507594`
- Issue: [#68](https://github.com/Team-Moru/moru-iOS/issues/68)

## Figma 기준

| 화면 | Node |
| --- | --- |
| Home content | `2045:1840` |
| Home skeleton | `2641:2345` |
| Profile | `1948:3859` |

3개 원본 PNG는 [`figma/`](figma/)에 scale 3, 1179 × 2556 px로 저장했다.

## 상태별 Before / After

| 상태 | Medium | AX3 |
| --- | --- | --- |
| home-regular | [Before](states/home-regular/light-M/before.png) · [After](states/home-regular/light-M/after.png) | [Before](states/home-regular/light-AX3/before.png) · [After](states/home-regular/light-AX3/after.png) |
| home-loading | [Before](states/home-loading/light-M/before.png) · [After](states/home-loading/light-M/after.png) | [Before](states/home-loading/light-AX3/before.png) · [After](states/home-loading/light-AX3/after.png) |
| home-empty | [Before](states/home-empty/light-M/before.png) · [After](states/home-empty/light-M/after.png) | [Before](states/home-empty/light-AX3/before.png) · [After](states/home-empty/light-AX3/after.png) |
| home-failure | [Before](states/home-failure/light-M/before.png) · [After](states/home-failure/light-M/after.png) | [Before](states/home-failure/light-AX3/before.png) · [After](states/home-failure/light-AX3/after.png) |
| home-partial-data | [Before](states/home-partial-data/light-M/before.png) · [After](states/home-partial-data/light-M/after.png) | [Before](states/home-partial-data/light-AX3/before.png) · [After](states/home-partial-data/light-AX3/after.png) |
| home-weather-denied | [Before](states/home-weather-denied/light-M/before.png) · [After](states/home-weather-denied/light-M/after.png) | [Before](states/home-weather-denied/light-AX3/before.png) · [After](states/home-weather-denied/light-AX3/after.png) |
| home-long-korean | [Before](states/home-long-korean/light-M/before.png) · [After](states/home-long-korean/light-M/after.png) | [Before](states/home-long-korean/light-AX3/before.png) · [After](states/home-long-korean/light-AX3/after.png) |
| profile-regular | [Before](states/profile-regular/light-M/before.png) · [After](states/profile-regular/light-M/after.png) | [Before](states/profile-regular/light-AX3/before.png) · [After](states/profile-regular/light-AX3/after.png) |
| profile-loading | [Before](states/profile-loading/light-M/before.png) · [After](states/profile-loading/light-M/after.png) | [Before](states/profile-loading/light-AX3/before.png) · [After](states/profile-loading/light-AX3/after.png) |
| profile-failure | [Before](states/profile-failure/light-M/before.png) · [After](states/profile-failure/light-M/after.png) | [Before](states/profile-failure/light-AX3/before.png) · [After](states/profile-failure/light-AX3/after.png) |
| profile-fallback-voice | [Before](states/profile-fallback-voice/light-M/before.png) · [After](states/profile-fallback-voice/light-M/after.png) | [Before](states/profile-fallback-voice/light-AX3/before.png) · [After](states/profile-fallback-voice/light-AX3/after.png) |
| profile-permission-off | [Before](states/profile-permission-off/light-M/before.png) · [After](states/profile-permission-off/light-M/after.png) | [Before](states/profile-permission-off/light-AX3/before.png) · [After](states/profile-permission-off/light-AX3/after.png) |
| profile-reset-unavailable | [Before](states/profile-reset-unavailable/light-M/before.png) · [After](states/profile-reset-unavailable/light-M/after.png) | [Before](states/profile-reset-unavailable/light-AX3/before.png) · [After](states/profile-reset-unavailable/light-AX3/after.png) |
| profile-long-korean | [Before](states/profile-long-korean/light-M/before.png) · [After](states/profile-long-korean/light-M/after.png) | [Before](states/profile-long-korean/light-AX3/before.png) · [After](states/profile-long-korean/light-AX3/after.png) |

각 variant의 `before-after/`에는 side-by-side, 50% overlay,
difference heatmap, metrics가 있다. `figma-after/`에는 Home regular,
Home loading, Profile regular의 canonical Medium 비교가 있다.

세부 내용은 [delta](delta.md), [exceptions](exceptions.md),
[tests](tests.md), [design QA](design-qa.md)를 참고한다.
