# Latest Design QA

- Latest completed pass: P1 Splash·온보딩
- Detailed report: [`Moru/docs/figma-pilot-review-bundle/P1-splash-onboarding/design-qa.md`](Moru/docs/figma-pilot-review-bundle/P1-splash-onboarding/design-qa.md)
- Source: Figma version `2379679754802507594`
- Scope: 13 states × Medium/AX3, 26 Before/After comparisons, 11 canonical
  Figma/After comparisons
- Open P0/P1/P2 findings: 0

final result: passed

---

# Historical: Figma Routine Screen Design QA

## Comparison Target

- Source visual truth:
  [Figma node 1278:212](https://www.figma.com/design/RNf4Q84fgsZf3V8MtZmGBc?node-id=1278-212)
- Source capture:
  `/private/tmp/moru-figma-routine-node-1278-212-393x852.png`
- Implementation capture:
  `/private/tmp/moru-figma-match-pass2-routine-393x852.png`
- Combined comparison:
  `/private/tmp/moru-figma-routine-comparison-pass2.png`
- Viewport: 393 × 852 points, iPhone 16 class
- State: light appearance, Medium Dynamic Type, one active routine, two inactive routines

## Density Normalization

- The Figma browser capture was 197 × 428 pixels at 50% canvas zoom.
- The source was normalized to 393 × 852 pixels for a 1:1 app-content comparison.
- The XCTest implementation render was 1179 × 2556 pixels at a 3× device scale.
- The implementation was normalized to 393 × 852 pixels.
- Status-bar and home-indicator rendering are system-owned. Their absence from the XCTest hierarchy
  render is not an app-content mismatch.

## Full-view Comparison Evidence

The final combined image shows matching 20-point side margins, title and section hierarchy,
100-point routine cards, active/inactive color states, toggle and chevron placement, the centered
add-routine card, and the compact bottom navigation region.

## Focused-region Comparison Evidence

The combined 1:1 image keeps the card text, icons, toggles, chevrons, section gaps, and tab labels
readable at native point size, so a separate enlarged crop was not required.

## Comparison History

### Pass 1

- [P1] The preview contained one active routine and an empty inactive state instead of the Figma
  state with one active and two inactive routines.
  - Fix: added deterministic Figma reference preview data for `활력 루틴`, `주말 루틴`, and
    `명상 루틴`.
- [P1] The bottom tab bar occupied 129 points including the safe area instead of the approximately
  99-point Figma region.
  - Fix: reduced the regular tab content minimum height from 95 to 65 points and matched the
    10-point tab label typography.
  - Regression note: the shared navigation geometry changed the Home, History, and Profile
    screenshot hashes. Their content was not changed by this work.
- [P2] Card content was too loose and shifted left because it used 16-point item spacing, 24-point
  insets, and a 44-point layout width for the chevron.
  - Fix: matched the 20-point card inset, 8-point compact row spacing, 20-point chevron layout, and
    preserved a 44-point interaction target with an expanded content shape.
- [P2] The metadata copy and typography did not match the source.
  - Fix: changed `소요 시간 15분` to `15분`, used 16-point titles and 12-point
    metadata, and matched the Figma item counts and durations.
- [P2] The inactive section and cards were too high.
  - Fix: replaced uniform container spacing with explicit 32/40/12-point section rhythm and
    16-point section-to-card spacing.

### Pass 2

- Post-fix evidence:
  `/private/tmp/moru-figma-routine-comparison-pass2.png`
- Fonts and typography: hierarchy, widths, weights, and copy match at the normalized viewport.
- Spacing and layout rhythm: margins, card geometry, section gaps, and tab-bar height match.
- Colors and visual tokens: active orange, inactive surface, text colors, and shadows use the
  existing matching asset-catalog tokens.
- Image and icon fidelity: the existing supplied routine, tab, toggle, and chevron assets are used;
  no placeholder or recreated raster asset remains.
- Copy and content: the visible titles, section labels, item counts, durations, and
  add action match.
- No actionable P0, P1, or P2 difference remains.

## Interactions Preserved

- Tapping the toggle persists the routine activation state.
- Tapping the chevron opens the selected routine editor.
- Tapping `새 루틴 추가하기` opens the new-routine editor.
- The four bottom tabs keep their existing navigation and accessibility identifiers.

## Follow-up Polish

- The normalized Figma browser capture is slightly softer than the native 3× implementation render
  because it was captured at 50% and upscaled. This is evidence quality, not an app defect.

final result: passed
