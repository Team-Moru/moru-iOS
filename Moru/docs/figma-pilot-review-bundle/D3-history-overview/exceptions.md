# D3 의도적 예외와 남은 차이

## 계산 계약 우선

- Figma는 기상 규칙성을 `73점`으로 표시하지만 현재 Domain 계약에서 편차 18분은
  `.consistent`와 `87점`이다. 계산 로직을 바꾸지 않고 `87점`을 유지했다.
- Figma의 `지난 주보다 12분 일찍`은 현재 모델에 전주 비교 값이 없으므로
  기존 `지난 기록 기준` 문구를 유지했다.
- Figma 2026년 4월의 날짜 시작 열과 실제 `ko_KR` Gregorian calendar가 다르다.
  fixture와 앱은 실제 calendar 계산 결과를 유지한다.

## Navigation 우선

- Figma heatmap에는 이전/다음 달 화살표가 있지만 v1 Overview에는 월 이동 계약이 없다.
  D3 범위에서 가짜 버튼이나 새 navigation을 추가하지 않고 year/month label만 표시했다.
- 기존 주간 완수율 날짜 상세와 최근 기록 navigation은 heatmap 아래 scroll content에
  유지했다.

## 상태 범위

- Figma는 regular Medium `1851:3687`과 loading Medium `2562:3611`만 제공한다.
- empty, failure, 부분 데이터, trial, streak 없음, 긴 한국어와 AX3는 기존 기능 의미를
  보존하면서 같은 pilot token과 responsive layout을 적용했다.
- History 모델에는 별도 trial flag가 없으므로 trial fixture는 데이터 1건,
  insufficient wake metrics, streak 없음 상태로 매핑했다.

## 비교 조건

- status bar와 home indicator는 앱 구현 대상이 아니므로 comparator에서 위 186 px,
  아래 102 px를 마스킹했다.
- Figma ↔ After mean absolute channel delta는 Overview `7.8092`,
  skeleton `3.6554`다.
- font anti-aliasing, SF Symbol과 Figma vector, SwiftUI glass/shadow 차이로 0-diff를
  목표로 하지 않는다.

## Canonical Before

- Before는 D0, D1, D2가 모두 병합된
  `main@fb5935c31f4401b98e2e30c0ff81ab64d79828ba`의 UI다.
- latest main 전용 clean worktree에 capture-only test와 자동 load 차단 option만
  임시 적용해 8상태 × Medium/AX3를 렌더했으며, 제품 코드는 변경하지 않았다.
- D1의 safe-area tab chrome과 D2의 완료 화면·visual baseline 변경을 포함한
  최신 main을 그대로 Before 기준으로 사용했다.
