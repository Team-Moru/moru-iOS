# P3 루틴 관리 변경 ledger

## 목록

- D1의 카드 구조와 활성 토글 동작을 그대로 유지했다.
- 메타 구분자를 `・`로 통일하고 `새 루틴 추가하기`를 Copy namespace로
  고정했다.
- 저장소 로드 실패는 빈 상태와 오류 문구를 중첩하지 않고 동일 design
  language의 복구 CTA로 표시한다.

## 생성·편집

- 편집기를 Figma의 flat input, 48 pt field, 62 pt step card,
  54 pt 고정 CTA rhythm으로 정리했다.
- 생성 CTA는 `완료`, 편집 CTA는 `저장`, 항목 CTA는
  `새 항목 추가하기`로 구분한다.
- 일정은 별도 전체 화면 대신 편집기 안의 펼침/접힘 영역으로 표시하되
  기존 draft binding과 저장 callback을 그대로 사용한다.
- 긴 한국어와 AX3에서는 title/summary/step row가 내용 높이로 확장되고
  scroll 흐름 안에서 CTA에 접근할 수 있다.

## 일정

- 요일 formatter는 `월 화 수 목 금・09시 00분` 형식이다.
- 시간 wheel은 앞/현재/뒤 3개 행과 선택 배경을 사용한다.
- Medium은 7개 요일을 한 줄에, AX3는 4열 grid로 재배치한다.
- 충돌 문구는 `수요일로 알림이 설정된…` 형태로 고정한다.

## 항목 시트

- 항목 추가/수정 sheet의 handle, title divider, 입력, 유형 3종, 시간,
  CTA 순서를 Figma와 맞췄다.
- 수정 시트에 `항목 삭제`를 제공하고 기존 step ID 및 preset metadata를
  유지한다.
- 선택된 항목 유형은 orange icon과 tint surface로 구분한다.

## 생성 방식 선택

- 전체 화면 선택기를 313 pt bottom sheet로 바꾸고 Figma에서 export한
  추천 orb와 직접 생성 calendar 이미지를 사용한다.
- 추천/직접 생성 선택 뒤에는 기존 로컬 추천 onboarding 또는 editor로
  이어지는 flow를 유지한다.
