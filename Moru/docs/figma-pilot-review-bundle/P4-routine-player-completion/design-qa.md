# P4 RoutinePlayer 및 완료 화면 디자인 QA

## 판정 기준

- Figma version: `2379679754802507594`
- Before: `main@dfd510bedf45c8b3156f97f5db99acad23f97d5b`
- 환경: iPhone 16, 393 × 852 pt, 3x, Light, `ko_KR`,
  `Asia/Seoul`
- 상태: RoutinePlayer 12개 + 완료 화면 5개, Medium/AX3
- 비교: Figma/implementation combined side-by-side, overlay,
  difference heatmap, metrics

## QA 반복

### Pass 1

- P1: orb source effect padding 때문에 실제 orb가 Figma보다 작았다.
  layout frame은 유지하고 source image만 1.33배 렌더했다.
- P1: regular progress/header와 항목 본문이 source보다 아래에 있었다.
  geometry를 source 좌표에 맞추고 trial header를 제거했다.
- P2: transcript가 orb와 중복되고 dialog hierarchy가 달랐다.
  transcript card 전환과 공통 dialog를 적용했다.

### Pass 2

- P2: 항목 완료 asset의 visible bounds가 source보다 작았다.
  완료 asset을 1.28배 조정했다.
- P2: transcript body color와 source glass hierarchy가 달랐다.
  token과 padding을 맞췄다.

### Pass 3

- P1: AX3에서 compact header와 상대 글꼴이 겹쳤다.
  title/action을 두 행으로 재배치하고 자연 line-height로 바꿨다.
- P1: AX3 timer gauge 내부 label과 값이 겹쳤다.
  fixed visual 내부 scaling을 제한하고 gauge accessibility label을
  유지했다.
- P2: 구조화 타이머의 번호 badge가 누락됐다.
  현재 단계 강조를 포함한 번호 badge를 추가했다.

## 최종 평가

- Typography: Medium의 title, metadata, guide와 dialog hierarchy가
  source와 일치한다. AX3는 자연 line-height와 wrapping을 사용한다.
- Layout/spacing: header, progress, orb/timer, transcript, voice control,
  skip action과 완료 화면이 같은 393 × 852 좌표계에서 검증됐다.
- Colors/surfaces: baby-blue canvas, orange progress, blue-gray type,
  glass card와 white dialog가 기존 design token을 사용한다.
- Imagery: 기존 orb, completion asset을 재사용하고 visible bounds만
  source에 맞췄다.
- Copy/content: preset별 안내, transcript title, 구조화 단계와
  저장 의미가 테스트로 고정됐다.
- States/interactions: 일반/체험, confirm/timer/input, step completion,
  dialog, retry/terminal error, run completion을 포함한다.
- Accessibility: AX3에서 overlap/crop 0건이며 필요한 화면은 scroll로
  모든 내용과 action에 접근할 수 있다.

## Canonical Medium Figma/After MAE

- regular-confirm: `12.353307881832423`
- confirm-transcript: `10.503696973918606`
- regular-timer: `12.82443542752574`
- regular-input: `12.695510252430266`
- input-long-korean: `15.934895040806461`
- structured-timer: `13.145058779457864`
- step-completed: `9.796387992722396`
- skip-dialog: `20.009257303648276`
- end-dialog: `19.861531319140937`
- trial-confirm: `11.290302938420355`
- completion-regular: `9.961476946947316`
- completion-trial: `7.914151409486439`

dialog MAE에는 서로 다른 blur raster가, timer/voice MAE에는 동적 상태
예외가 포함된다.

## 자체 리뷰

- P0: 0
- P1: 0
- P2: 0

final result: passed
