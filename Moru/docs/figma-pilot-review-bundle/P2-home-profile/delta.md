# P2 Home·Profile 변경 ledger

## Home

- Header는 Figma의 glow, 20 pt horizontal inset, 제목·설명 위계를 적용했다.
  이름은 `LocalProfile.displayName`을 유지하고 미확정 상태에는 이름을 꾸며내지 않는다.
- 오늘 루틴과 streak를 184 pt glass card, 24 pt radius, 112 pt progress ring,
  요일 check와 최고 기록 구조로 맞췄다.
- weather card를 84 pt glass surface로 맞추고 실제 온도, 상태, 갱신 시각과
  기존 refresh action을 유지했다.
- 현재·활성 루틴은 Figma surface, spacing, typography를 적용하면서 실제 routine,
  진행률, step, callback과 accessibility identifier를 유지했다.
- cold loading은 Figma skeleton과 동일한 두 개 184 pt block, 84 pt weather block,
  326 pt routine block을 고정 geometry로 렌더한다.

## Profile

- 화면 제목은 Figma의 `설정`을 유지하고, 마이 탭을 `음성 설정`, `계정`,
  `데이터 관리` 세 섹션으로 정리했다.
- 프로필 카드는 비로그인 상태에서 splash MORU 마크와 `소셜 로그인`을,
  연결된 상태에서 provider 이름의 `계정 연결됨`을 표시한다.
- 음성 행에는 선택된 음성의 설명을 노출하지 않고 `모루 말투`만 표시한다.
- `소셜 로그인` 행은 Apple·Google·카카오의 실제 인증 흐름을 시작하는
  피그마 스타일 bottom sheet를 연다. 연결 후에는 `로그아웃`, `회원탈퇴`만
  계정 섹션에 남긴다.
- 데이터 관리는 `로컬 데이터 초기화`와 기존 확인 dialog를 유지한다.
- AX3에서는 카드가 내용 높이로 확장되고 긴 한국어 이름을 생략하지 않으며,
  tab bar는 기존 D1 접근성 계약에 따라 icon-only로 유지한다.

## Assets

- Home streak 불꽃은 Figma node `2394:2688`의 scale 3 PNG를 전용 asset으로
  추가해 기존 1x 소스의 확대 흐림을 제거했다.
- 나머지 아이콘은 앱의 기존 SF Symbols와 design-system tab icon을 유지했다.
