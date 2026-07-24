# P3 루틴 관리 의도적 예외

## 기능 사실 우선

- Figma의 `AI 추천 루틴 만들기`, `ai가 자동으로` 문구는 사용하지 않는다.
  현재 앱은 `LocalTemplateSuggestionService` 기반이므로
  `추천 루틴 만들기`, `로컬 템플릿을 추천해요`로 정확히 설명한다.
- Figma 일정 화면 아래의 사운드·날씨·운세 layer는 v1 기능에 없으므로
  추가하지 않는다.
- Figma expanded schedule의 summary와 선택 원이 서로 다른 요일을
  표시하는 layer 불일치는 복제하지 않는다. 실제 draft의 선택값 하나를
  summary와 selector가 함께 사용한다.

## 동적 데이터·validation

- Figma 샘플의 빈 설명, 항목명, 시간, 루틴 수는 하드코딩하지 않는다.
  캡처는 실제 model fixture를 사용한다.
- 새 루틴 기본 이름 `새 루틴`, 최소 한 개 항목 validation, 저장 시점은
  기존 계약을 유지한다. 따라서 Figma의 빈 이름/빈 항목인데 활성화된
  `완료`·`저장` CTA 상태는 복제하지 않는다.
- step type, instruction, `presetItemID`, required flag와 ID는 편집 후에도
  보존한다.

## 접근성 우선

- 항목 유형의 선택 card는 Figma처럼 peach tint surface와 orange icon을
  유지하지만, 낮은 대비의 흰색 label은 사용하지 않고 orange accent
  label로 표시한다.

## 비교 환경

- Figma PNG에는 status bar와 home indicator가 있고 deterministic XCTest
  fixture에는 system chrome가 없을 수 있어 top 186 px, bottom 102 px를
  metrics에서 마스킹한다.
- Figma backdrop의 샘플 화면과 구현 backdrop의 실제 editor fixture가
  달라 bottom sheet/dialog 전체 MAE에는 의도적 동적 content 차이가 포함된다.
- Figma 미제공 empty/error/긴 한국어/AX3는 기존 기능과 공통 token을
  기준으로 판정한다.
