# P4 — RoutinePlayer 및 완료 화면

- Base / Canonical Before: `main@dfd510bedf45c8b3156f97f5db99acad23f97d5b`
- Branch: `fix/#72-routine-player-completion-figma-polish`
- Figma file: `RNf4Q84fgsZf3V8MtZmGBc`
- Figma version: `2379679754802507594`
- Issue: [#72](https://github.com/Team-Moru/moru-iOS/issues/72)

## Figma 기준

| 화면 | Node |
| --- | --- |
| 확인형 — 안내 | `1461:2561` |
| 확인형 — 음성 결과 | `1464:3248` |
| 타이머형 | `1467:3697` |
| 입력형 — 대기 | `1656:1101` |
| 입력형 — 긴 한국어 결과 | `1559:716` |
| 구조화 스트레칭 | `1656:891` |
| 항목 완료 | `1661:2335` |
| 건너뛰기 대화상자 | `2564:4193` |
| 루틴 종료 대화상자 | `2564:4350` |
| 체험 실행 | `2753:9706` |
| 일반 완료 | `1656:1043` |
| 체험 완료 | `2644:2839` |

원본 16개 PNG는 [`figma/`](figma/)에 scale 3,
1179 × 2556 px로 보존했다.

## 검증 산출물

- [`states/`](states/): canonical Before/After, Medium/AX3
- [`comparisons/`](comparisons/): Figma/After side-by-side, 50% overlay,
  difference heatmap, metrics
- [delta](delta.md), [exceptions](exceptions.md), [tests](tests.md),
  [design QA](design-qa.md)

RoutinePlayer 12개 상태와 완료 화면 5개 상태를 검증했다. 반복 캡처는
동일 PNG임을 테스트에서 확인하며, 저장소에는 각 상태의 canonical
1장만 둔다.
