# MORU design QA index

## Onboarding alarm card refinement

Detailed evidence and final judgment:
[`Moru/docs/figma-pilot-review-bundle/alignment-checkpoint-2-alarm-card/design-qa.md`](Moru/docs/figma-pilot-review-bundle/alignment-checkpoint-2-alarm-card/design-qa.md)

- Source: user-provided comparison image plus Figma `2379679754802507594`.
- Scope: alarm-card copy, spacing, sound slider, and weather/fortune toggles.
- Result: the sound bar is operable, both choices are interactive and persisted, the card no longer overlaps the CTA, and masked full-screen MAE improved from 16.264 to 15.291.

## P3 routine management

Detailed evidence and final judgment:
[`Moru/docs/figma-pilot-review-bundle/P3-routine-management/design-qa.md`](Moru/docs/figma-pilot-review-bundle/P3-routine-management/design-qa.md)

- Source: Figma `2379679754802507594`, iPhone 16, Light, Medium/AX3.
- Scope: list, creation choice, creation, editing, schedule, item editing, deletion, and weekday conflict.
- Evidence: 12-state Before/After set and nine canonical Figma/After pairs.
- Self-review: P0 0, P1 0, P2 0.

## Cross-flow alignment checkpoint 1

Detailed evidence and final judgment:
[`Moru/docs/figma-pilot-review-bundle/alignment-checkpoint-1/design-qa.md`](Moru/docs/figma-pilot-review-bundle/alignment-checkpoint-1/design-qa.md)

- Source: Figma `2379679754802507594`, iPhone 16, Light, Medium/AX3, plus 375 pt alarm-width coverage.
- Scope: onboarding goals/alarm, home weather geometry, player input/confirmation/timer, and routine completion.
- Result: all six representative comparisons passed their MAE gates; 46 selected tests passed, 3 opt-in captures skipped, and the Release simulator build passed.
- Remaining deviations are documented as P3 or backend-dependent.

final result: passed
