# D2 디자인 QA

## 판정 기준

- Source: Figma `1656:1043`, `2644:2839`, scale 3
- Figma version: `2379679754802507594`
- Before: `main@9e89776e1fa4dc075423bddd7ba2b45899a953d4`
- After: rebased D2 branch
- Viewport: iPhone 16, 393 × 852 pt, Light, Medium/AX3
- System mask: top 186 px, bottom 102 px

## Medium

- regular와 trial의 제목 baseline, glow 중심, 완료율 card 위치와 CTA 계층이
  Figma source와 일치한다.
- regular의 streak card, 2열 단계 목록, 두 CTA와 trial의 1열 목록, 단일 CTA가
  각각 source 구조를 유지한다.
- regular Figma↔After mean absolute channel delta는 `9.978310418608222`다.
- trial Figma↔After mean absolute channel delta는 `7.922860448800511`다.
- trial CTA 문구만 v1 기능 계약에 따라 `홈으로`를 유지한 의도적 예외다.

## AX3와 상태

- regular와 trial: 제목·부제·완수율 값에 겹침이나 잘림이 없고 의미 순서를 유지한다.
- streak 없음: streak card 없이 단계와 CTA가 자연스럽게 이어진다.
- 완료 단계 없음: 기존 empty 문구가 온전히 표시되고 CTA는 ScrollView로 접근한다.
- 긴 한국어: 단계 목록이 1열로 reflow되고 각 제목이 생략 없이 여러 줄로 표시된다.
- 모든 상태의 primary/repeat PNG가 byte-identical이다.
- AX3 line-height review 전후 Medium 다섯 상태 PNG는 byte-identical이다.

## Rebase와 line-height 통합 확인

- 첫 AX3 재캡처에서 D0 exact line-height와 D2 레이아웃 조합의 글자 겹침을 P1으로
  발견했다.
- 제목·부제의 multiline sizing을 보강한 뒤, D0 전역 modifier를 바꾸지 않고
  D2 화면 한정으로 `style.lineHeight`를 글꼴과 같은 Dynamic Type 기준에서
  scale·반올림한 exact line-height를 적용했다.
- regular, trial, streak 없음, 완료 단계 없음, 긴 한국어의 AX3를 이전 natural
  line-height 캡처와 side-by-side로 직접 비교했다. 모든 상태에서 글자 겹침,
  glyph 잘림이 재발하지 않았다. trial과 streak 없음 상태의 CTA도 온전히 표시된다.
- Medium 이미지는 line-height review 수정 전후 byte-identical이며 Figma 정합성을
  유지한다.

## 증거 한계

- PNG는 ScrollView의 첫 viewport만 보여 준다. regular, 완료 단계 없음, 긴 한국어의
  화면 아래 CTA 접근은 screenshot만으로 단정하지 않고, 기존 ScrollView 코드와
  functional gate로 별도 확인했다.
- VoiceOver 읽기 순서와 실제 scroll gesture는 정적 PNG만으로 완전 검증할 수 없다.

## 심각도

- P0: 0
- P1: 0
- P2: 0

`final result: passed`
