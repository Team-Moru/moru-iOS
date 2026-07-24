# P5 디자인 QA

## 판정 기준

- Figma 승인 version: `2379679754802507594`
- Before: `main@2e3351358285c226efda18c64d65c99e34d00ca1`
- 환경: iPhone 16, 393 × 852 pt, 3x, Light, `ko_KR`, `Asia/Seoul`
- 상태: weekly 3, daily 3, run 4, missing destination 1
- 크기: Medium, AX3
- 비교: Figma/Before/After side-by-side, overlay, absolute-difference

## 최종 결과

- 구조: 주간·데일리·실행 상세의 summary와 section 순서가 승인 Figma와 일치한다.
- 간격: 20 pt horizontal inset, 54 pt header, 24 pt card radius와 section
  rhythm을 확인했다.
- 색상: pale canvas, coral summary/accent, blue completion icon, glass surface를
  pilot token으로 통일했다.
- 타이포: Medium은 승인 hierarchy를 유지하고 AX3는 세로 reflow와 자연 높이를
  사용한다.
- 상태: loading, empty, error, permission-off, partial-data를 Medium/AX3에서
  확인했다.
- 긴 한국어: 제목, transcript, 결과 row가 잘림 없이 줄바꿈되고 스크롤로
  접근 가능하다.

## 자체 리뷰

- P0: 0
- P1: 0
- P2: 0
- 중간 QA에서 AX3 실행 상세의 back/title 충돌과 오류 CTA의 tab-bar overlap을
  발견했다. chevron back과 accessibility status alignment/CTA를 적용한 뒤
  전체 상태를 다시 캡처해 해소를 확인했다.
- D1 고정 tab chrome은 유지하며 상세 본문은 tab safe area 아래까지 스크롤된다.

## Pixel gate

- raw capture: 1179 × 2556 px
- mask: top 186 px + bottom 102 px
- invariant: `comparedPixelCount == 2673972`,
  `maskedPixelCount == 339552`, `maximumChannelDelta <= 255`
- Figma↔After mean absolute channel delta:
  - weekly: `10.162339146907048` (gate ≤ 11)
  - daily: `9.726162926662408` (gate ≤ 10)
  - run: `14.114769713370222` (gate ≤ 15)
- Before↔After differing pixel range:
  `2.7845093366721865%...99.7442755571113%`
- Before↔After는 legacy surface에서 P5 layout으로 이동한 change ledger이므로
  similarity 상한을 적용하지 않는다.
