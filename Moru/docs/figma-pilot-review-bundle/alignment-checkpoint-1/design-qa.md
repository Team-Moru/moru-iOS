# Figma alignment design QA

## Source of truth

- Figma file: `RNf4Q84fgsZf3V8MtZmGBc`
- Figma version: `2379679754802507594` (captured 2026-08-05, source modified 2026-07-24)
- Reference exports: `/Users/minhyeok/.codex/visualizations/2026/08/05/019fd040-c9ed-7d33-880f-0acf992bfed8/moru-figma-current-audit/figma`
- Original implementation captures: `/Users/minhyeok/.codex/visualizations/2026/08/05/019fd040-c9ed-7d33-880f-0acf992bfed8/moru-figma-current-audit/current`
- Original side-by-side pairs: `/Users/minhyeok/.codex/visualizations/2026/08/05/019fd040-c9ed-7d33-880f-0acf992bfed8/moru-figma-current-audit/pairs`
- Updated implementation captures and comparisons: `/Users/minhyeok/.codex/visualizations/2026/08/05/019fd040-c9ed-7d33-880f-0acf992bfed8/moru-figma-alignment-checkpoint-1`

## Capture contract

- Native iOS viewport: 393 × 852 pt, rendered 1179 × 2556 px at 3×.
- Narrow-phone check: 375 × 812 pt, rendered at 3×.
- Appearance and locale: Light, `ko_KR`, `Asia/Seoul`.
- Dynamic Type: Medium and AX3.
- CSS viewport/device scale factor: not applicable to native SwiftUI.
- System status-bar and home-indicator regions are excluded from numerical comparisons.

## Compared representative states

| State | Figma reference | Updated implementation | Full comparison | MAE before → after | Gate |
| --- | --- | --- | --- | ---: | --- |
| Onboarding goals | `figma/onboarding-goals.png` | `onboarding/goals-light-M.png` | `comparisons/onboarding-goals/side-by-side.png` | 11.543 → 10.440 | ≤ 12, pass |
| Onboarding alarm | `figma/onboarding-alarm.png` | `onboarding/alarm-light-M.png` | `comparisons/onboarding-alarm/side-by-side.png` | 17.596 → 16.264 | ≤ 18, pass |
| Home | `figma/home.png` | `home-profile/home-regular-light-M.png` | `comparisons/home/side-by-side.png` | 7.652 → 7.652 | ≤ 8, pass |
| Player confirmation | `figma/player-confirm.png` | `player/regular-confirm-light-M.png` | `comparisons/player-confirm/side-by-side.png` | 12.353 → 8.540 | ≤ 10, pass |
| Player timer | `figma/player-timer.png` | `player/regular-timer-light-M.png` | `comparisons/player-timer/side-by-side.png` | 12.824 → 9.306 | ≤ 10, pass |
| Routine completion | `figma/routine-completion.png` | `completion/regular-light-M.png` | `comparisons/routine-completion/side-by-side.png` | 9.961 → 9.180 | ≤ 10, pass |

Paths in the table are relative to their corresponding source or updated-capture roots above. Each updated comparison directory also contains `overlay.png`, `difference-heatmap.png`, and `metrics.json`.

Focused-region crops were not required for this checkpoint: the six selected screens contain no open sheet or dialog, and the 3× full-screen comparisons make every modified component readable. Player dialog states were separately captured in both Medium and AX3 under the updated `player` directory.

## Comparison history and resolved findings

| Severity | Finding | Iteration and evidence | Resolution |
| --- | --- | --- | --- |
| P1 | Onboarding goal chips used rigid rows and drifted from the Figma wrapping and vertical rhythm. | Initial pair `pairs/onboarding-goals.png`; updated pair `comparisons/onboarding-goals/side-by-side.png`. | Replaced rigid rows with an intrinsic SwiftUI flow layout and aligned title/content spacing. |
| P1 | Alarm content, options, and footer competed for height; AX3 could visually crowd the CTA. | Initial pair `pairs/onboarding-alarm.png`; updated Medium and AX3 captures under `onboarding`. | Added a fixed safe-area CTA, scrollable content, responsive title spacing, and a Figma-aligned options card. |
| P1 | The seven 44 pt weekday targets overflowed at 375 pt width. | Post-fix capture `onboarding/alarm-light-M-375.png`; `testAlarmRendersAtNarrowPhoneWidth`. | Derived inter-item spacing from available width while preserving 44 pt targets. No clipping remains. |
| P1 | Player fixtures represented different semantic states from Figma, inflating visual error. | Initial player pairs; updated `comparisons/player-confirm` and `comparisons/player-timer`. | Aligned deterministic confirmation, transcript, waveform, timer, and active-step fixtures to the Figma states. |
| P2 | Player progress, transcript card, timer gauge, and completion treatment lacked Figma polish. | Medium and AX3 capture matrix under `player` and `completion`. | Added the 5 pt gradient progress treatment, glass transcript surface, 218 pt timer gauge, refined cards, glow, and spacing. |
| P1 | A comparison could falsely pass when masks removed every pixel in the ROI. | Manual negative checks against `Scripts/figma-visual-compare.swift`. | The tool now rejects empty comparison regions and masks that remove all rows; both negative checks exit non-zero. |
| P2 | Home weather cards used one height for informational and actionable states. | Updated home/profile capture matrix and `testWeatherCardHeightContract`. | Kept the normal card at 84 pt and reserved 104 pt for error or permission actions. |

## Fidelity review

- Typography: existing MORU type tokens remain authoritative; title hierarchy, timer scale, control labels, and AX3 wrapping were visually checked.
- Spacing and geometry: onboarding flow, alarm footer, weekday targets, player cards, timer gauge, progress bar, and weather-card heights were measured and tested.
- Color and tokens: existing MORU orange, blue player gradient, semantic surfaces, borders, and disabled colors are reused.
- Asset fidelity: existing SF Symbols and app assets are retained; no placeholder, emoji, or hand-drawn replacement asset was introduced.
- Copy and content: Korean Figma copy and representative states are aligned where implemented.
- States and accessibility: Medium and AX3 matrices cover loading, failure, long Korean text, dialogs, completion variants, and player variants. Controls below the initial AX3 fold remain inside a scroll view.

## Intentional deviations

- Weather narration, fortune narration, and an in-app sound catalog have no production backend in this scope. They are shown truthfully as disabled with `준비 중`; sound points to iPhone settings rather than pretending to be selectable.
- System status-bar and home-indicator rendering differs between Figma export and simulator capture and is masked from metrics.
- AX3 prioritizes readable type and 44 pt targets. Some secondary player or alarm controls move below the first fold but remain reachable by scrolling.

## Residual risk

- Remaining differences are P3: small glyph rasterization, font-metric, and platform rendering differences.
- Home did not need a visual redesign in the selected regular state because it already met the numerical gate; only state-specific weather-card geometry changed.
- This checkpoint does not implement backend-dependent account lifecycle, StoreKit/PRO catalog, real voice catalog, or spoken weather/fortune.

## Verification

- Eight selected XCTest classes: 46 passed, 3 opt-in screenshot tests skipped, 0 failures after intentional visual baseline approval.
- Narrow alarm-width test: passed at 375 × 812 pt.
- Release simulator build: passed.
- Visual-compare negative checks: passed by correctly rejecting zero-pixel comparisons.
- `git diff --check`: passed before commit.

final result: passed
