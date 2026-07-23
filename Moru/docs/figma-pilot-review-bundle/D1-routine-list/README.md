# D1 — 루틴 목록 Figma 세부 보정

- Base: `main@b5ae957f1fef6152ae713842339d6a91d351bebe`
- Branch: `fix/#60-routine-list-figma-polish`
- Figma file: `RNf4Q84fgsZf3V8MtZmGBc`
- Figma node: `2387:2961`
- Figma version: `2379679754802507594`
- Figma last modified: `2026-07-24T07:06:38Z`
- Issue: [#60](https://github.com/Team-Moru/moru-iOS/issues/60)

## 증거

| 항목 | Medium | AX3 |
| --- | --- | --- |
| Before | [normal Before](states/normal/light-M/before.png) | [normal Before](states/normal/light-AX3/before.png) |
| After | [normal After](states/normal/light-M/after.png) | [normal After](states/normal/light-AX3/after.png) |
| Side-by-side | [Figma↔After](comparisons/normal-light-M/figma-after/side-by-side.png) · [Before↔After](comparisons/normal-light-M/before-after/side-by-side.png) | [Before↔After](comparisons/normal-light-AX3/before-after/side-by-side.png) |
| 50% overlay | [Figma↔After](comparisons/normal-light-M/figma-after/overlay.png) · [Before↔After](comparisons/normal-light-M/before-after/overlay.png) | [Before↔After](comparisons/normal-light-AX3/before-after/overlay.png) |
| Diff | [Figma↔After](comparisons/normal-light-M/figma-after/difference-heatmap.png) · [Before↔After](comparisons/normal-light-M/before-after/difference-heatmap.png) | [Before↔After](comparisons/normal-light-AX3/before-after/difference-heatmap.png) |
| Metrics | [Figma↔After](comparisons/normal-light-M/figma-after/metrics.json) · [Before↔After](comparisons/normal-light-M/before-after/metrics.json) | [Before↔After](comparisons/normal-light-AX3/before-after/metrics.json) |

Figma API 3x 원본은 [`figma/node-2387-2961.png`](figma/node-2387-2961.png)에
있다. [`states/`](states/)에는 normal, empty, partial-empty, alarm-warning,
long-korean 상태의 Medium/AX3 Before·After가 있다.

## 비교 산출물

- `comparisons/normal-light-M/figma-after/`: Figma와 After 비교
- `comparisons/normal-light-M/before-after/`: 기준 브랜치와 After 비교
- `comparisons/normal-light-AX3/before-after/`: 기준 브랜치와 After 비교

각 디렉터리는 `side-by-side.png`, `overlay.png`,
`difference-heatmap.png`, `metrics.json`을 포함한다. 비교 시 상단 상태 영역
186 px와 하단 홈 인디케이터 영역 102 px를 제외했고, diff gain은 4이다.

픽셀 차이 수치는 렌더러·글꼴 안티앨리어싱과 AX3 재배치를 포함하는 진단값이며,
합격 임계값으로 사용하지 않는다. 구조와 기능 보존 판단은 이미지, fixture 테스트,
회귀 테스트를 함께 본다.

세부 내용은 [delta](delta.md), [exceptions](exceptions.md),
[tests](tests.md), [design QA](design-qa.md),
[environment](environment.json)를 참고한다.

## 원본 SHA-256

- Figma: `e52b2a29e7a70862c2ca679842d738a37e8dea3eadd52f274665104c697b6d5b`
- Before normal M: `16c37f9ef2d4dba2cdf5e731fec5131f701beba8bebdca212fff083a87077ac2`
- After normal M: `719574234a7bc35dcf0704fc6ad5dc9f301b0031a73a6f7cf7949e6be0bc3f9c`
- Before normal AX3: `a5f14263a7afb0d6bf893ff06fd4e24d303427755359501d76e0825b702549e0`
- After normal AX3: `5f82a217a4df2d722f3824db072749e48e8ead9cd29f824eb9dcd883373df405`
