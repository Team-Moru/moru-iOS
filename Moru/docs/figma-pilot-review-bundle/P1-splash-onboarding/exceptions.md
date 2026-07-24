# P1 의도적 예외

- Figma의 interactive welcome CTA(`2644:2640`)는 bootstrap/navigation 계약을 바꾸므로
  구현하지 않았다. loading Splash(`2644:2751`, `2644:2797`)의 시각 자산만 적용했다.
- Figma의 `AI가 정리한`, `AI가 분석하고 있어요`는 로컬 템플릿 구현 사실과 충돌해
  `로컬 템플릿`, `루틴을 정리하고 있어요`로 표시한다.
- Figma의 PRO/전체 음성/추가 음성은 제공하지 않는다. 번들 MP3와 연결된 4종만 보인다.
- Figma 알람의 날씨, 운세, 사운드 선택은 실제 기능이 없어 노출하지 않는다.
- 알람 시간은 정적 `07:00 AM` 장식 대신 기존 증감 조작성을 유지한 wheel control로
  표현한다. 그래서 alarm Figma/After MAE는 별도 기능 예외로 평가한다.
- 추천 routine의 `6개 / 총 15분`과 routine 이름은 sample 값이다. After는
  `LocalTemplateSuggestionService`가 반환한 실제 step 수, 시간, 이름을 표시한다.
- 상태바와 home indicator는 XCTest hierarchy render에 없으므로 비교에서 상단 186 px,
  하단 102 px를 마스킹했다.
