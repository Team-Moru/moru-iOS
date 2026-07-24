# P4 변경 요약

## 실행 화면

- 일반 실행의 상단 navigation, progress, 항목 수와 본문 간격을 Figma
  좌표계에 맞췄다. 체험 실행은 source처럼 header 없이 progress부터
  시작한다.
- 확인형과 입력형은 preset ID 기반 안내 문구를 사용한다. 사용자 항목은
  저장된 instruction을 우선해 사실과 다른 고정 문구를 만들지 않는다.
- 음성 입력 결과는 orb 대신 glass transcript card로 전환하며, 긴 한국어
  문장은 자연스럽게 줄바꿈한다.
- 기본 타이머와 단계가 있는 스트레칭 타이머를 분리했다. 스트레칭은
  번호 badge, 단계 문구와 시간을 표시한다.
- 음성 안내 재생, 음성 인식, transcript, MP3/STT 자동 완료,
  guidance 대기와 기존 callback은 유지했다.

## 완료 및 대화상자

- 항목 완료 화면의 progress/header, 완료 asset 크기와 문구 위치를
  Figma에 맞췄다.
- 건너뛰기/종료 확인을 공통 `MoruDialog`에 정렬하고 정확한 저장 의미를
  안내한다.
- D2에서 구현된 일반/체험 완료 화면은 P4 환경에서 다시 캡처하고
  navigation, streak, run 요약과 trial 비저장 의미가 유지됨을 확인했다.

## 접근성

- AX3에서 header action을 별도 행으로 재배치하고 실행 본문을 scroll
  가능하게 했다.
- 대화상자 action은 세로로 확장한다.
- 고정 원형 gauge 내부 숫자는 겹치지 않게 크기를 제한하되 전체
  `남은 시간` 값은 하나의 accessibility label로 노출한다.
- 긴 transcript와 구조화 단계는 잘리지 않고 높이로 확장된다.
