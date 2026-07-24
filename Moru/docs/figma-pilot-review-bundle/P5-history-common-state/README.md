# P5 History·공통 상태 Figma 보정

P5는 History 주간/데일리/실행 상세를 승인 Figma 구조로 보정하고,
로딩·빈 상태·오류·권한·부분 데이터 상태의 Medium/AX3 회귀를 확인한다.

## 범위

- 주간 리포트: coral 3-metric summary, 요일별 완수율, 항목별 분석
- 데일리 리포트: 완수율·소요 시간·기상 시각, 오늘의 기록, 항목별 결과
- 실행 상세: 실제 실행 날짜와 snapshot 기반 기록/결과
- 공통 상태: loading, empty, error, permission-off, partial-data
- 접근성: Dynamic Type Medium/AX3와 긴 한국어

## 증거 구조

- `figma/`: 승인 Figma 원본과 393 pt 비교용 실행 상세 정규화 이미지
- `figma-after/`: 주간·데일리·실행 상세 Figma↔After 비교
- `states/`: 11상태 × Medium/AX3 Before↔After 원본 및 비교
- `common-states/`: 공통 상태 최종 캡처와 반복 렌더
- `environment.json`: 기준 commit, Figma version, 캡처 환경
- `delta.md`, `exceptions.md`, `design-qa.md`, `tests.md`: 변경·예외·QA·검증 기록

모든 비교는 1179 × 2556 px 캔버스에서 상태바 186 px와 home indicator
102 px를 마스킹했다.
