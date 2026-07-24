# D1 루틴 목록 델타

## 구조

- 루틴 목록에 D0의 `figmaPilot` 컴포넌트 스타일을 선택적으로 적용했다.
- 기존 데이터 흐름, 토글 동작, 알림 권한 재시도, 편집·추가 내비게이션은 변경하지 않았다.
- 메인 탭도 파일럿 스타일을 선택하며 다른 호출부는 기본 `legacy` 스타일을 유지한다.

## 간격과 크기

- 화면 좌우 여백 20 pt, 활성 카드 높이 100 pt, 카드 모서리 24 pt를 맞췄다.
- 비활성 카드 사이 간격을 16 pt로 맞췄다.
- 카드 내부 아이콘은 40 pt, 아이콘과 설명은 12 pt, 토글과 chevron은 4 pt로 맞췄다.
- 하단 CTA는 높이 60 pt, 모서리 24 pt를 적용했다.
- 탭 항목 폭 60 pt, 항목 간격 32 pt, 상단 콘텐츠 여백 15 pt를 적용했다.
- iPhone 16 하단 safe area 34 pt를 합산해 Medium 탭의 화면 내 높이를 95 pt로 맞췄다.

## 타이포그래피

- 화면 제목은 H3 24/33.6 semibold와 gray550을 사용한다.
- 섹션 제목은 B4 16/22.4 semibold와 gray400을 사용한다.
- 카드 본문은 B3, 보조 문구는 C1, 탭 레이블은 C2를 사용한다.

## 색상과 표면

- 화면 배경은 pilot canvas 색을 사용한다.
- 활성 카드는 Figma tint, 비활성 카드는 반투명 white와 pilot shadow를 사용한다.
- CTA와 빈 상태 액션은 pilot primary 버튼 표현을 사용한다.
- 탭 바는 pilot 반투명 표면과 상단 shadow를 사용한다.

## 접근성 재배치

- AX3에서 카드 내부 요소가 겹치지 않도록 텍스트와 액션을 세로로 재배치한다.
- D0의 exact line-height는 Medium에서 그대로 사용하고, AX3에서는 같은 font
  scale·weight를 자연 line-height로 렌더해 glyph 잘림과 줄 겹침을 방지한다.
- 탭은 AX3 최소 콘텐츠 높이를 70 pt로 늘리고 safe area와 함께 유지한다.
- 큰 empty CTA나 긴 카드가 있어도 탭이 viewport 밖으로 밀리지 않도록 bottom
  safe-area inset으로 탭 영역을 예약한다.
- 내용이 화면 높이를 넘으면 기존 ScrollView로 접근하며 기능 요소를 숨기지 않는다.

## D0 병합 반영

- exact base를 D0 merge `b5ae957f`로 이동했다.
- D0 review fix의 중복 tab `minHeight` 제거와 exact Medium line-height를 보존했다.
- D1 고유 pilot tab geometry와 legacy 분기만 충돌 해결 결과로 유지했다.
