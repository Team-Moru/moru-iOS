# D3 History Overview 디자인 QA

## 판정 기준

- Figma 승인 version: `2379679754802507594`
- Before: `main@fb5935c31f4401b98e2e30c0ff81ab64d79828ba`
- 환경: iPhone 16, 393 × 852 pt, 3x, Light, `ko_KR`, `Asia/Seoul`
- 상태: regular, loading, empty, failure, partial-data, trial, no-streak,
  long-korean
- 크기: Medium, AX3
- 비교: Figma/Before/After, side-by-side, 50% overlay, absolute-difference

## 구조·간격·타이포·색상·컴포넌트

- 구조: streak와 주간 상태를 첫 coral card로 통합하고, 기상 패턴과 월간 heatmap을
  Figma 순서로 배치했다. 기존 주간 완수율과 최근 기록은 스크롤 하단에 유지했다.
- 간격: Medium의 20 pt horizontal inset, 54 pt header, 32 pt section 간격,
  114 pt summary card와 D1의 95 pt tab chrome을 확인했다.
- 타이포: Medium은 D0 exact line-height를 유지한다. AX3는 History 화면 한정 자연
  line-height를 사용해 제목, metric, weekday와 retry CTA가 잘리지 않는다.
- 색상: canvas, coral accent, blue inactive weekday, heatmap scale과 glass surface가
  승인 token을 사용한다.
- 컴포넌트: 주간 card, wake metric, heatmap, loading skeleton, empty/failure 상태가
  동일한 radius와 surface 계층을 사용한다.

## 상태별 결과

- regular Medium: Figma와 직접 비교했으며 구조와 핵심 geometry가 일치한다.
- loading Medium: Figma skeleton과 직접 비교했으며 card/header geometry가 일치한다.
- empty/failure Medium·AX3: 중앙 정렬, 메시지 줄바꿈과 retry CTA 접근을 확인했다.
- partial-data/trial/no-streak: 계산 불가·기록 부족 의미를 유지하고 overflow가 없다.
- long-korean: responsive card와 ScrollView를 유지하며 첫 viewport에 겹침이 없다.
- AX3 regular: summary card가 세로로 reflow되고 weekday가 adaptive grid로 배치된다.
- AX3 전체: 콘텐츠는 ScrollView로 접근하며 tab safe area 뒤에 영구적으로 가려지는
  CTA가 없다.

## 자체 리뷰

- P0: 0
- P1: 0
- P2: 0
- AX3 exact line-height로 발생했던 제목·weekday·retry CTA 잘림은 수정 후
  8상태를 재캡처해 해소를 확인했다.
- Medium 8상태는 AX3 fallback 수정 전후 byte-identical이다. retry CTA를 로컬
  responsive label로 바꾼 failure Medium만 최종 상태로 다시 비교했다.
- 상태바 186 px와 home indicator 102 px는 pixel metrics에서 마스킹했다.
- Figma 예시값과 기능 계약의 차이는 `exceptions.md`에 기록했다.

## 재현 가능한 pixel gate

- Figma/After similarity gate:
  - regular Medium mean absolute channel delta ≤ `10`; actual `7.809242081318229`
  - loading Medium mean absolute channel delta ≤ `5`; actual `3.655436307236326`
- 모든 raw capture는 1179 × 2556 px이고 같은 fixture의 반복 render와 PNG byte가 같다.
- 모든 metrics는 `comparedPixelCount == 2673972`,
  `maskedPixelCount == 339552`, `maximumChannelDelta <= 255`를 만족해야 한다.
- Before/After는 legacy UI에서 승인 D3 UI로 바뀐 change ledger이므로 similarity 상한을
  적용하지 않는다. 16개 비교의 differing pixel 범위 `91.4822%...99.9213%`는
  canvas, card 구조, tab chrome과 AX3 reflow의 의도적 변경을 포함한다.
- 큰 diff의 검토 근거:
  - empty AX3 `99.6696%`: legacy empty surface에서 pilot canvas, icon, 자연 line-height와
    D1 tab chrome으로 바뀐 결과다.
  - no-streak Medium `99.7165%`, AX3 `99.1015%`: legacy streak/wake/weekly card를
    coral summary, wake pattern, heatmap 순서로 재배치하고 AX3를 세로 reflow한 결과다.
  - partial-data AX3 `99.9086%`: 같은 구조 변경에 sparse data와 insufficient metric
    표현이 함께 적용된 결과다.
- 위 Before/After 상태는 side-by-side와 overlay를 직접 검토했으며 P0/P1/P2가 없다.

final result: passed
