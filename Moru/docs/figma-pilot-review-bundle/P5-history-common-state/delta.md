# P5 변경 내역

## History 상세

- 주간 리포트의 검은 summary를 coral 3-metric card로 교체하고 실제 주간
  완수율, 전주 대비 percentage point, 완료 실행 평균 소요 시간을 표시한다.
- 주간 summary는 Medium에서 Figma와 같은 제목→값 순서를 사용하고,
  AX3에서는 값→제목으로 reflow해 큰 글씨에서도 값과 레이블을 안전하게 읽는다.
- 요일별 완수율을 Figma bar chart와 같은 순서·상단 coral→하단 투명 gradient·
  surface로 보정했다.
- 데일리/실행 상세는 `오늘의 기록`을 `항목별 결과`보다 먼저 배치했다.
- 기록 card는 저장된 transcript만 표시한다. 저장되지 않은 step type·step 소요
  시간·copy/share 액션은 만들어내지 않는다.
- 실행 상세 제목은 snapshot의 실제 실행 날짜를 사용한다.
- 기존 NavigationStack의 back 동작과 History 탭의 이동 경로는 유지한다.

## 공통 상태와 접근성

- History empty/failure/missing destination을 같은 상태 surface로 통합했다.
- 상태 화면은 스크롤 가능하며 AX3에서 CTA가 탭 바 뒤에 남지 않도록 상단
  정렬하고 CTA가 자연 높이로 확장되게 했다.
- AX3 상세 header는 back label을 chevron으로 축약해 실제 날짜 제목과
  겹치지 않는다. 접근성 label과 hint는 유지한다.
- 빈 transcript, step 결과 없음, 부분 실행은 별도 empty/partial 문구로 표시한다.

## 변경하지 않은 계약

- completion rate와 주간 비교 계산
- 삭제·reset 동작
- History navigation
- `RoutineRun` snapshot 의미
- Domain/Data/SwiftData schema, migration, repository, dependency boundary
