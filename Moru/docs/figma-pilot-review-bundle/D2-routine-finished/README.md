# D2 — 루틴 완료 화면

- Base: `main@9e89776e1fa4dc075423bddd7ba2b45899a953d4`
- Branch: `fix/#62-routine-finished-figma-polish`
- Canonical Before: `main@9e89776e1fa4dc075423bddd7ba2b45899a953d4`
- Figma file: `RNf4Q84fgsZf3V8MtZmGBc`
- Figma version: `2379679754802507594`
- Issue: [#62](https://github.com/Team-Moru/moru-iOS/issues/62)

## Figma 기준

| 역할 | Node | 원본 |
| --- | --- | --- |
| regular 완료 | `1656:1043` | [PNG](figma/node-1656-1043.png) |
| trial 완료 | `2644:2839` | [PNG](figma/node-2644-2839.png) |

## 상태별 Before / After

| 상태 | Medium | AX3 |
| --- | --- | --- |
| regular | [Before](states/regular/light-M/before.png) · [After](states/regular/light-M/after.png) | [Before](states/regular/light-AX3/before.png) · [After](states/regular/light-AX3/after.png) |
| trial | [Before](states/trial/light-M/before.png) · [After](states/trial/light-M/after.png) | [Before](states/trial/light-AX3/before.png) · [After](states/trial/light-AX3/after.png) |
| streak 없음 | [Before](states/no-streak/light-M/before.png) · [After](states/no-streak/light-M/after.png) | [Before](states/no-streak/light-AX3/before.png) · [After](states/no-streak/light-AX3/after.png) |
| 완료 단계 없음 | [Before](states/no-completed-steps/light-M/before.png) · [After](states/no-completed-steps/light-M/after.png) | [Before](states/no-completed-steps/light-AX3/before.png) · [After](states/no-completed-steps/light-AX3/after.png) |
| 긴 한국어 단계 | [Before](states/long-korean/light-M/before.png) · [After](states/long-korean/light-M/after.png) | [Before](states/long-korean/light-AX3/before.png) · [After](states/long-korean/light-AX3/after.png) |

AX3 After는 글꼴과 같은 Dynamic Type 기준으로 140% token line-height를
scale·반올림해 적용한 최종 캡처다. 다섯 상태 모두 겹침과 잘림 없이 reflow된다.

## 비교 산출물

| 비교 | Side-by-side | Overlay | Diff | Metrics |
| --- | --- | --- | --- | --- |
| regular Figma ↔ After | [보기](states/regular/light-M/figma-after/side-by-side.png) | [보기](states/regular/light-M/figma-after/overlay.png) | [보기](states/regular/light-M/figma-after/difference-heatmap.png) | [JSON](states/regular/light-M/figma-after/metrics.json) |
| trial Figma ↔ After | [보기](states/trial/light-M/figma-after/side-by-side.png) | [보기](states/trial/light-M/figma-after/overlay.png) | [보기](states/trial/light-M/figma-after/difference-heatmap.png) | [JSON](states/trial/light-M/figma-after/metrics.json) |
| regular Before ↔ After (M) | [보기](states/regular/light-M/before-after/side-by-side.png) | [보기](states/regular/light-M/before-after/overlay.png) | [보기](states/regular/light-M/before-after/difference-heatmap.png) | [JSON](states/regular/light-M/before-after/metrics.json) |
| regular Before ↔ After (AX3) | [보기](states/regular/light-AX3/before-after/side-by-side.png) | [보기](states/regular/light-AX3/before-after/overlay.png) | [보기](states/regular/light-AX3/before-after/difference-heatmap.png) | [JSON](states/regular/light-AX3/before-after/metrics.json) |
| trial Before ↔ After (M) | [보기](states/trial/light-M/before-after/side-by-side.png) | [보기](states/trial/light-M/before-after/overlay.png) | [보기](states/trial/light-M/before-after/difference-heatmap.png) | [JSON](states/trial/light-M/before-after/metrics.json) |
| trial Before ↔ After (AX3) | [보기](states/trial/light-AX3/before-after/side-by-side.png) | [보기](states/trial/light-AX3/before-after/overlay.png) | [보기](states/trial/light-AX3/before-after/difference-heatmap.png) | [JSON](states/trial/light-AX3/before-after/metrics.json) |
| streak 없음 Before ↔ After (M) | [보기](states/no-streak/light-M/before-after/side-by-side.png) | [보기](states/no-streak/light-M/before-after/overlay.png) | [보기](states/no-streak/light-M/before-after/difference-heatmap.png) | [JSON](states/no-streak/light-M/before-after/metrics.json) |
| streak 없음 Before ↔ After (AX3) | [보기](states/no-streak/light-AX3/before-after/side-by-side.png) | [보기](states/no-streak/light-AX3/before-after/overlay.png) | [보기](states/no-streak/light-AX3/before-after/difference-heatmap.png) | [JSON](states/no-streak/light-AX3/before-after/metrics.json) |
| 완료 단계 없음 Before ↔ After (M) | [보기](states/no-completed-steps/light-M/before-after/side-by-side.png) | [보기](states/no-completed-steps/light-M/before-after/overlay.png) | [보기](states/no-completed-steps/light-M/before-after/difference-heatmap.png) | [JSON](states/no-completed-steps/light-M/before-after/metrics.json) |
| 완료 단계 없음 Before ↔ After (AX3) | [보기](states/no-completed-steps/light-AX3/before-after/side-by-side.png) | [보기](states/no-completed-steps/light-AX3/before-after/overlay.png) | [보기](states/no-completed-steps/light-AX3/before-after/difference-heatmap.png) | [JSON](states/no-completed-steps/light-AX3/before-after/metrics.json) |
| 긴 한국어 Before ↔ After (M) | [보기](states/long-korean/light-M/before-after/side-by-side.png) | [보기](states/long-korean/light-M/before-after/overlay.png) | [보기](states/long-korean/light-M/before-after/difference-heatmap.png) | [JSON](states/long-korean/light-M/before-after/metrics.json) |
| 긴 한국어 Before ↔ After (AX3) | [보기](states/long-korean/light-AX3/before-after/side-by-side.png) | [보기](states/long-korean/light-AX3/before-after/overlay.png) | [보기](states/long-korean/light-AX3/before-after/difference-heatmap.png) | [JSON](states/long-korean/light-AX3/before-after/metrics.json) |

세부 내용은 [delta](delta.md), [exceptions](exceptions.md),
[tests](tests.md), [design QA](design-qa.md)를 참고합니다.
