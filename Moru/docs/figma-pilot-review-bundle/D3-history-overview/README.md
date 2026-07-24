# D3 — 이력 Overview

- Base: `main@fb5935c31f4401b98e2e30c0ff81ab64d79828ba`
- Branch: `fix/#64-history-overview-figma-polish`
- Canonical Before: `main@fb5935c31f4401b98e2e30c0ff81ab64d79828ba`
- Figma file: `RNf4Q84fgsZf3V8MtZmGBc`
- Figma version: `2379679754802507594`
- Issue: [#64](https://github.com/Team-Moru/moru-iOS/issues/64)

## Figma 기준

| 역할 | Node | 원본 |
| --- | --- | --- |
| History Overview | `1851:3687` | [PNG](figma/node-1851-3687.png) |
| History skeleton | `2562:3611` | [PNG](figma/node-2562-3611.png) |

## 상태별 Before / After

| 상태 | Medium | AX3 |
| --- | --- | --- |
| regular | [Before](states/regular/light-M/before.png) · [After](states/regular/light-M/after.png) | [Before](states/regular/light-AX3/before.png) · [After](states/regular/light-AX3/after.png) |
| loading | [Before](states/loading/light-M/before.png) · [After](states/loading/light-M/after.png) | [Before](states/loading/light-AX3/before.png) · [After](states/loading/light-AX3/after.png) |
| empty | [Before](states/empty/light-M/before.png) · [After](states/empty/light-M/after.png) | [Before](states/empty/light-AX3/before.png) · [After](states/empty/light-AX3/after.png) |
| failure | [Before](states/failure/light-M/before.png) · [After](states/failure/light-M/after.png) | [Before](states/failure/light-AX3/before.png) · [After](states/failure/light-AX3/after.png) |
| 부분 데이터 | [Before](states/partial-data/light-M/before.png) · [After](states/partial-data/light-M/after.png) | [Before](states/partial-data/light-AX3/before.png) · [After](states/partial-data/light-AX3/after.png) |
| trial | [Before](states/trial/light-M/before.png) · [After](states/trial/light-M/after.png) | [Before](states/trial/light-AX3/before.png) · [After](states/trial/light-AX3/after.png) |
| streak 없음 | [Before](states/no-streak/light-M/before.png) · [After](states/no-streak/light-M/after.png) | [Before](states/no-streak/light-AX3/before.png) · [After](states/no-streak/light-AX3/after.png) |
| 긴 한국어 | [Before](states/long-korean/light-M/before.png) · [After](states/long-korean/light-M/after.png) | [Before](states/long-korean/light-AX3/before.png) · [After](states/long-korean/light-AX3/after.png) |

각 상태와 variant의 `before-after/` 폴더에는 side-by-side, overlay,
difference heatmap, metrics가 함께 있습니다.

## 대표 비교 산출물

| 비교 | Side-by-side | Overlay | Diff | Metrics |
| --- | --- | --- | --- | --- |
| Overview Figma ↔ After | [보기](states/regular/light-M/figma-after/side-by-side.png) | [보기](states/regular/light-M/figma-after/overlay.png) | [보기](states/regular/light-M/figma-after/difference-heatmap.png) | [JSON](states/regular/light-M/figma-after/metrics.json) |
| Skeleton Figma ↔ After | [보기](states/loading/light-M/figma-after/side-by-side.png) | [보기](states/loading/light-M/figma-after/overlay.png) | [보기](states/loading/light-M/figma-after/difference-heatmap.png) | [JSON](states/loading/light-M/figma-after/metrics.json) |
| regular Before ↔ After (M) | [보기](states/regular/light-M/before-after/side-by-side.png) | [보기](states/regular/light-M/before-after/overlay.png) | [보기](states/regular/light-M/before-after/difference-heatmap.png) | [JSON](states/regular/light-M/before-after/metrics.json) |
| regular Before ↔ After (AX3) | [보기](states/regular/light-AX3/before-after/side-by-side.png) | [보기](states/regular/light-AX3/before-after/overlay.png) | [보기](states/regular/light-AX3/before-after/difference-heatmap.png) | [JSON](states/regular/light-AX3/before-after/metrics.json) |
| loading Before ↔ After (M) | [보기](states/loading/light-M/before-after/side-by-side.png) | [보기](states/loading/light-M/before-after/overlay.png) | [보기](states/loading/light-M/before-after/difference-heatmap.png) | [JSON](states/loading/light-M/before-after/metrics.json) |
| loading Before ↔ After (AX3) | [보기](states/loading/light-AX3/before-after/side-by-side.png) | [보기](states/loading/light-AX3/before-after/overlay.png) | [보기](states/loading/light-AX3/before-after/difference-heatmap.png) | [JSON](states/loading/light-AX3/before-after/metrics.json) |

세부 내용은 [delta](delta.md), [exceptions](exceptions.md),
[tests](tests.md), [design QA](design-qa.md)를 참고합니다.
