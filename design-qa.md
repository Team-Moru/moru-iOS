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

## Guided routine identity and step editor

### Evidence

- Source visual truth: `/var/folders/b4/jz3tn3_53gl8ldwcmc9cmmch0000gn/T/codex-clipboard-d35545a2-3c7f-4b9c-b22a-deb4796eeefd.png`
- Implementation screenshot: `/private/tmp/moru-figma-p1-after/recommended-addition-existing-routine-review-light-M.png`
- State: 새 루틴 추가 → 추천 루틴 만들기 → 루틴 있어요 → 정리된 루틴
- Native viewport: 393 × 852 points, Light mode, standard Dynamic Type
- Source pixels: 434 × 166 (component crop; density metadata unavailable)
- Implementation pixels: 1179 × 2556 at 3×, corresponding to 393 × 852 points
- Density normalization: the source is a focused component crop, so the comparison used the
  visible `루틴` field region rather than rescaling the full implementation screen.

### Findings

- No actionable P0, P1, or P2 mismatch was found.
- Fonts and typography: the section label, entered routine name, and placeholder preserve the
  app's approved onboarding type scale and hierarchy.
- Spacing and layout rhythm: the two 48-point rounded fields, horizontal insets, border radius,
  and vertical gap match the reference structure.
- Colors and visual tokens: canvas, white input surface, neutral border, primary text, and muted
  placeholder use the existing Moru semantic tokens and visually match the source.
- Image quality and assets: this component contains no image assets; no substitute or rasterized
  UI was introduced.
- Copy and content: the section label is `루틴`, the generated title remains editable, and the
  empty second field displays `루틴 설명` for user input.

### Comparison History

- Initial comparison: no P0/P1/P2 issue. The implementation screenshot shows the requested field
  structure and the same screen also exposes the selected routine cards with `−` controls.
- No visual-fix iteration was required after the comparison.

### Full-view and Focused Evidence

- Full view: the implementation was checked at the complete 393 × 852 native viewport for safe
  scrolling, footer placement, and surrounding section rhythm. The source only defines the field
  component, so unrelated full-screen regions were not treated as visual truth.
- Focused region: both opened artifacts show the `루틴` label, populated name field, empty
  `루틴 설명` field, matching rounded borders, and equivalent spacing.

### Implementation Checklist

- [x] Keep the generated routine name editable.
- [x] Start generated routine descriptions empty and persist user input.
- [x] Reuse the same identity fields in onboarding and recommended-addition reviews.
- [x] Verify `+/-` candidate editing for all three experience choices.
- [x] Run deterministic visual captures and update the intentional baseline change.

final result: passed
