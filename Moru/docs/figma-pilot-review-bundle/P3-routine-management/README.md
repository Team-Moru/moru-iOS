# P3 — 루틴 관리

- Base / Canonical Before: `main@437084e4ed8cc02e4c759b69e95e8775d8006e25`
- Branch: `fix/#70-routine-management-figma-polish`
- Figma file: `RNf4Q84fgsZf3V8MtZmGBc`
- Figma version: `2379679754802507594`
- Issue: [#70](https://github.com/Team-Moru/moru-iOS/issues/70)

## Figma 기준

| 화면 | Node |
| --- | --- |
| 루틴 목록 | `2387:2961` |
| 루틴 수정 — 일정 접힘 | `2257:2067` |
| 루틴 수정 — 일정 펼침 | `2261:3433` |
| 항목 수정 | `2389:3332` |
| 루틴 삭제 | `2389:3486` |
| 요일 충돌 | `2738:2303` |
| 생성 방식 선택 | `2389:3650` |
| 빈 루틴 생성 | `2387:2714` |
| 항목 추가 | `2389:3224` |

9개 원본 PNG는 [`figma/`](figma/)에 scale 3,
1179 × 2556 px로 저장했다.

## 상태별 Before / After

| 상태 | Medium | AX3 |
| --- | --- | --- |
| routine-list | [Before](states/routine-list/light-M/before.png) · [After](states/routine-list/light-M/after.png) | [Before](states/routine-list/light-AX3/before.png) · [After](states/routine-list/light-AX3/after.png) |
| editor-collapsed | [Before](states/editor-collapsed/light-M/before.png) · [After](states/editor-collapsed/light-M/after.png) | [Before](states/editor-collapsed/light-AX3/before.png) · [After](states/editor-collapsed/light-AX3/after.png) |
| editor-schedule | [Before](states/editor-schedule/light-M/before.png) · [After](states/editor-schedule/light-M/after.png) | [Before](states/editor-schedule/light-AX3/before.png) · [After](states/editor-schedule/light-AX3/after.png) |
| step-edit | [Before](states/step-edit/light-M/before.png) · [After](states/step-edit/light-M/after.png) | [Before](states/step-edit/light-AX3/before.png) · [After](states/step-edit/light-AX3/after.png) |
| delete-dialog | [Before](states/delete-dialog/light-M/before.png) · [After](states/delete-dialog/light-M/after.png) | [Before](states/delete-dialog/light-AX3/before.png) · [After](states/delete-dialog/light-AX3/after.png) |
| weekday-conflict | [Before](states/weekday-conflict/light-M/before.png) · [After](states/weekday-conflict/light-M/after.png) | [Before](states/weekday-conflict/light-AX3/before.png) · [After](states/weekday-conflict/light-AX3/after.png) |
| creation-choice | [Before](states/creation-choice/light-M/before.png) · [After](states/creation-choice/light-M/after.png) | [Before](states/creation-choice/light-AX3/before.png) · [After](states/creation-choice/light-AX3/after.png) |
| create-empty | [Before](states/create-empty/light-M/before.png) · [After](states/create-empty/light-M/after.png) | [Before](states/create-empty/light-AX3/before.png) · [After](states/create-empty/light-AX3/after.png) |
| step-add | [Before](states/step-add/light-M/before.png) · [After](states/step-add/light-M/after.png) | [Before](states/step-add/light-AX3/before.png) · [After](states/step-add/light-AX3/after.png) |
| editor-long-korean | [Before](states/editor-long-korean/light-M/before.png) · [After](states/editor-long-korean/light-M/after.png) | [Before](states/editor-long-korean/light-AX3/before.png) · [After](states/editor-long-korean/light-AX3/after.png) |
| list-empty | [Before](states/list-empty/light-M/before.png) · [After](states/list-empty/light-M/after.png) | [Before](states/list-empty/light-AX3/before.png) · [After](states/list-empty/light-AX3/after.png) |
| list-error | [Before](states/list-error/light-M/before.png) · [After](states/list-error/light-M/after.png) | [Before](states/list-error/light-AX3/before.png) · [After](states/list-error/light-AX3/after.png) |

각 variant의 `before-after/`에는 side-by-side, 50% overlay,
difference heatmap, metrics가 있다. [`figma-after/`](figma-after/)에는
9개 canonical Medium 비교가 있다.

세부 내용은 [delta](delta.md), [exceptions](exceptions.md),
[tests](tests.md), [design QA](design-qa.md)를 참고한다.
