# Onboarding alarm card design QA

## Source of truth

- User comparison image: `/Users/minhyeok/.codex/attachments/d3f17747-ee3d-4457-b3c2-577ef8c5b5b4/codex-clipboard-693a5eaf-6110-4a2f-b6a5-1ce8a339fd14.png`
- Figma export: `/Users/minhyeok/.codex/visualizations/2026/08/05/019fd040-c9ed-7d33-880f-0acf992bfed8/moru-figma-current-audit/figma/onboarding-alarm.png`
- Previous implementation: `/Users/minhyeok/.codex/visualizations/2026/08/05/019fd040-c9ed-7d33-880f-0acf992bfed8/moru-figma-alignment-checkpoint-1/onboarding/alarm-light-M.png`
- Final captures and comparisons: `/Users/minhyeok/.codex/visualizations/2026/08/05/019fd040-c9ed-7d33-880f-0acf992bfed8/moru-alarm-refinement`

## Scope and capture contract

- Scope is limited to the onboarding alarm card, its copy, spacing, sound control, and weather/fortune controls.
- Native iOS viewport: 393 × 852 pt, rendered at 3× in Light mode and `ko_KR`.
- Dynamic Type: Medium and AX3; 375 × 812 pt narrow-width coverage remains enabled.
- Full comparison: `full-comparison.png`.
- Focused comparison: `card-comparison.png`.
- Pixel evidence: `comparisons/full/side-by-side.png`, `overlay.png`, `difference-heatmap.png`, and `metrics.json`.

## Comparison history and resolved findings

| Severity | Finding | Fix | Final evidence |
| --- | --- | --- | --- |
| P1 | The sound bar was a disabled constant slider, so it looked interactive but could not be operated. | Added a visible UIKit slider bridged through `MPVolumeView`; dragging changes the device media/output volume on device. | `testAlarmSoundGuidanceCopyAndVisualContract`; focused comparison. |
| P1 | Weather and fortune controls were disabled, included `준비 중` badges, and did not preserve user choice. | Replaced them with interactive Figma-style toggles and propagated both values through onboarding and routine persistence requests. | `testAlarmNarrationOptionsUpdateThePreviewSchedule`; targeted onboarding tests. |
| P2 | Header copy differed from Figma (`iPhone 설정` instead of centered `다음` and `레디얼 >`). | Matched the three-part header and updated the sound name/copy. | `card-comparison.png`. |
| P1 | The first revised card was too tall and collided with the fixed bottom CTA. | Reduced normal-size vertical padding, control heights, and gaps while keeping AX3 content scrollable. | Final Medium capture; no card/CTA overlap. |
| P2 | The card margin, speaker symbol, slider thumb, and toggle geometry differed visibly. | Matched the 25 pt outer card margin, orange one-wave speaker, explicit orange slider thumb, and white toggle knobs. | `card-comparison.png`. |

## Fidelity review

- Card outer edge, internal left alignment, header copy, orange control color, and control order now track the Figma reference.
- The final full-screen masked MAE is 15.291, improved from checkpoint 1's 16.264 and below the existing onboarding-alarm gate of 18.
- Medium content is fully visible above the CTA. AX3 retains readable type and scroll access instead of shrinking content.
- Existing MORU typography, colors, radius, shadow, and SF Symbols remain authoritative.
- The sound control is not a fake per-alarm volume setting. iOS does not expose a separate alarm-volume API here, so the control truthfully adjusts device media/output volume through the system volume view.
- Weather and fortune preferences are now interactive and persisted. Producing the actual spoken weather/fortune content remains dependent on narration content/service work outside this card-only scope.

## Verification

- `OnboardingFigmaVisualTests`: sound control contract, deterministic Medium/AX3 capture, narrow width, and persisted option state passed.
- `OnboardingHappyPathTests`: onboarding completion and persistence passed.
- `RecommendedRoutineCreationTests`: recommended-flow save and conflict paths passed.
- `git diff --check`: passed.
- Reference and implementation were reviewed together in both full-screen and focused three-column comparison boards.

final result: passed
