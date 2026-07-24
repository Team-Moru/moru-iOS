# D2 루틴 완료 화면 델타

## 구조

- `1656:1043`은 저장된 일반 실행의 regular 완료 상태로 매핑했다.
- `2644:2839`는 저장하지 않는 온보딩 trial 완료 상태로 매핑했다.
- regular는 완료율, streak, 완료 단계, 기록 확인과 홈 CTA를 유지한다.
- trial은 완료율, 완료 단계, 단일 summary exit CTA로 구성한다.
- 실행 저장, streak 계산, 기록 이동, summary exit callback은 변경하지 않았다.

## 배경과 glow

- 화면 배경을 Figma의 상단 `#E6EDFF`에서 canvas `#F3F6FC`로 이어지는 gradient로 맞췄다.
- 기존 `moruGradientGlow` 원본 asset을 393 × 450 pt로 배치하고 위쪽 47 pt를
  확장해 Figma glow 영역과 맞췄다.

## 간격과 크기

- Medium에서 title 시작 247 pt, title-card 간격 51 pt를 적용했다.
- 완료율 card는 353 × 90 pt, streak card는 353 × 86 pt, radius 24 pt다.
- regular 단계 목록은 2열, 6 pt 행 간격이며 CTA는 353 × 54 pt다.
- trial 단계 목록은 Figma처럼 가운데 1열이고 CTA는 349 × 54 pt다.
- safe area를 제외한 393 × 852 pt viewport에서 CTA가 home indicator 위에 위치한다.

## 타이포그래피와 색상

- 제목은 H2 28/39.2 semibold, 부제는 B4 16/22.4 medium을 사용한다.
- 카드 제목과 단계는 C1 14/19.6, 완료율과 streak 값은 H3 24/33.6을 사용한다.
- 제목 `gray600`, 본문 `gray400`, 카드 label/단계 `gray350`, 값 `gray450`을 적용했다.
- 완료율은 `orange150 → orange350` gradient와 `gray250` sparkle을 사용한다.

## 카드와 CTA

- card는 white 20% glass surface, radial border, pilot shadow를 사용한다.
- regular streak card는 현재 연속 일수를 Figma처럼 가운데 정렬한다.
- 최고 streak 값은 화면에서 중복 노출하지 않고 accessibility label에 유지한다.
- 기존 두 callback은 그대로 유지하며 trial은 summary exit callback 하나만 노출한다.

## 접근성 재배치

- AX3에서 단계 목록은 1열로 전환하고 긴 단계명은 여러 줄로 표시한다.
- D0의 Medium exact line-height는 유지한다. AX3에서는 D2 화면 한정 modifier가
  글꼴과 같은 Dynamic Type 기준으로 token line-height를 scale·반올림한 뒤
  exact line-height로 적용한다.
- 제목·부제의 무제한 multiline sizing과 1열 reflow를 함께 유지해 AX3에서도
  글자 겹침이나 잘림이 생기지 않는다.
- 전체 내용은 기존 `ScrollView`에서 의미 순서대로 탐색하고 CTA까지 스크롤 접근한다.
- 완료율 card, streak card, 완료 단계에는 합성된 VoiceOver label을 제공한다.
