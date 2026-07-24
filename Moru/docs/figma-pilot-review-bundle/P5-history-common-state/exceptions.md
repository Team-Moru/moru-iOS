# P5 Figma 예외

## 데이터와 기능 계약 우선

- Figma 주간 예시의 평균 소요 시간은 `13:48`이지만 fixture snapshot에서 계산된
  `11:12`를 표시한다.
- 전주 대비는 단순 percent가 아니라 percentage point이므로 `+8%p`로 표시한다.
- Figma 실행 상세의 예시 날짜와 앱 fixture 날짜가 달라 앱의 실제 실행 날짜를
  사용한다.
- Figma의 step type·step elapsed는 현재 snapshot에 없으므로 표시하지 않는다.
- Figma의 copy/share와 완료 전용 `홈으로` CTA는 연결된 기능이 없어 추가하지
  않는다. 기존 back/navigation을 유지한다.
- Figma 예시 항목명 대신 저장된 `RoutineRun` step title을 사용한다.

## 비교 정규화

- Figma node `2564:4072`는 394 pt 폭(1182 px)으로 export된다. 앱의 고정
  비교 캔버스 393 pt(1179 px)에 맞춰
  `node-2564-4072-normalized.png`를 1179 × 2556 px로 정규화했다.
- 상태바 186 px와 home indicator 102 px는 시스템 상태 차이이므로 모든 pixel
  metrics에서 제외한다.
