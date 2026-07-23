# D1 디자인 QA

## 판정 기준

- Source: Figma node `2387:2961`, scale 3
- Before: `main@b5ae957f1fef6152ae713842339d6a91d351bebe`
- After: rebased D1 branch
- Viewport: iPhone 16, 393 × 852 pt, Light, Medium/AX3
- System mask: top 186 px, bottom 102 px

## Medium

- header, section baseline, 20 pt screen inset가 source 구조와 일치한다.
- active/inactive card의 100 pt 높이, 24 pt radius, 내부 icon·text·toggle·chevron
  순서와 간격이 일치한다.
- inactive card 16 pt gap, 60 pt CTA, 95 pt safe-area 포함 tab chrome이 일치한다.
- Figma↔After mean absolute channel delta는 `4.313836370263663`이다.

## AX3와 상태

- normal: 카드 내부 glyph 잘림·겹침 없이 세로 reflow되며 tab이 고정된다.
- empty: header, 설명, CTA와 tab이 같은 viewport에서 접근 가능하다.
- partial-empty: empty section과 active card 의미 순서를 유지한다.
- alarm-warning: 기존 경고·재시도 콘텐츠를 유지하며 카드에서 접근 가능하다.
- long-korean: 긴 이름은 잘리지 않고 줄바꿈되며 후속 콘텐츠는 스크롤로 접근한다.

## 심각도

- P0: 0
- P1: 0
- P2: 0

`final result: passed`
