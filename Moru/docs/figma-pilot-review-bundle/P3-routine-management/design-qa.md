# P3 루틴 관리 디자인 QA

## 판정 기준

- Figma version: `2379679754802507594`
- Before: `main@437084e4ed8cc02e4c759b69e95e8775d8006e25`
- 환경: iPhone 16, 393 × 852 pt, 3x, Light, `ko_KR`, `Asia/Seoul`
- 상태: 12개, Medium/AX3
- 비교: source/implementation combined side-by-side, overlay, heatmap, metrics

## QA 반복

### Pass 1

- P1: 기존 schedule이 editor와 분리된 전체 화면이라 Figma의 inline
  accordion 구조와 달랐다.
  - 수정: 같은 draft binding을 사용하는 inline schedule로 전환했다.
- P1: 기존 editor의 alarm card, 76 pt step row와 큰 section 간격이
  Figma보다 과도했다.
  - 수정: flat alarm summary, 62 pt row, 48 pt input과 54 pt CTA로 맞췄다.

### Pass 2

- P1: 생성 방식 선택이 전체 화면이고 generic SF Symbol을 사용했다.
  - 수정: 313 pt bottom sheet와 Figma export 2개를 적용했다.
- P2: 추천 orb source의 effect padding 때문에 실제 orb가 작게 보였다.
  - 수정: layout 폭은 유지하고 source만 1.72배 렌더해 Figma visible
    bounds에 맞췄다.
- P2: 항목 수정 fixture가 Figma와 다른 confirm state였다.
  - 수정: timer 3분 상태로 맞춰 selected surface와 duration을 비교했다.

### Pass 3

- P1: 로드 실패가 empty state 아래에 오류 문구를 추가해 의미가 겹쳤다.
  - 수정: 전용 error state와 `다시 불러오기` 복구 CTA로 분리했다.
- P2: 선택된 항목 유형 icon이 dark source color를 유지했다.
  - 수정: 선택 icon에 accent tint를 적용했다.
- P2: system detent의 bottom safe area 때문에 생성 sheet가 Figma보다
  높았다.
  - 수정: visible 346 pt에 맞도록 detent content height를 313 pt로 조정했다.

## 최종 평가

- Typography: Medium은 기존 Moru text style의 exact line-height를 사용하고,
  AX3는 자연 line-height와 wrapping을 사용한다.
- Layout/spacing: list card, editor input, schedule wheel, step row, fixed CTA,
  bottom sheet가 Figma hierarchy와 rhythm을 따른다.
- Colors/surfaces: pilot canvas, accent orange, blue-gray text, white card와
  muted selection surface가 승인 token을 사용한다.
- Imagery/icons: 생성 선택의 orb/calendar는 Figma scale 3 export다.
  기존 semantic routine icon과 chevron은 design system을 사용한다.
- Copy/content: 고정 copy와 formatter는 `RoutineManagementCopy`로 검증한다.
  동적 루틴·step 값은 model을 우선한다.
- States/interactions: CRUD, reorder, 활성 토글, 충돌 해결, 알람 예약,
  validation, callback과 accessibility identifier를 유지한다.
- Accessibility: AX3에서 input/row/header/sheet는 높이로 확장되고 scroll로
  접근 가능하다. weekday는 4열로 reflow하며 wheel은 adjustable action을
  제공한다.

## Pixel 기록

- Canonical Medium Figma/After MAE:
  - routine-list `4.311902542983496`
  - editor-collapsed `7.498121770409962`
  - editor-schedule `9.607928205680539`
  - step-edit `15.206629064677317`
  - delete-dialog `13.97809126896866`
  - weekday-conflict `16.189100209974775`
  - creation-choice `14.536729504522361`
  - create-empty `8.142540884247603`
  - step-add `15.811579802132059`
- sheet/dialog MAE에는 Figma와 구현 backdrop fixture 및 기능 사실 예외가
  함께 포함된다.
- 24개 Before/After metrics는 `comparedPixelCount == 2673972`,
  `maskedPixelCount == 339552`를 만족한다.

## 자체 리뷰

- P0: 0
- P1: 0
- P2: 0

final result: passed
