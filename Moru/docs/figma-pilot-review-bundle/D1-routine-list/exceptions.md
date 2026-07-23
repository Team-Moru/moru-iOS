# D1 예외 기록

## Figma에 없는 상태

Figma node `2387:2961`은 normal Medium 상태만 제공한다. 다음 상태는 별도의
Figma 화면을 발명하지 않고 기존 기능 콘텐츠를 보존한 채 같은 pilot 토큰을 적용했다.

- empty
- partial-empty
- alarm-warning
- long-korean
- 모든 AX3 화면

## Dynamic Type

AX3는 393 × 852 pt 안에서 모든 루틴과 CTA를 동시에 고정 노출하는 대신 기존
스크롤 동작을 유지한다. 카드 내부 겹침을 막고 탭 접근성을 유지하는 것을 우선한다.
따라서 AX3 Before·After의 큰 픽셀 차이는 Figma 불일치가 아니라 의도한 reflow를
포함한다.

D0의 Figma exact line-height는 Medium 판정에 유지한다. AX3에서는 Pretendard
glyph가 exact line box를 넘어서 잘리거나 겹치므로 같은 Dynamic Type scale과
weight를 유지한 자연 line-height로 전환한다. 이는 D0 token 값을 되돌리는 변경이
아니라 루틴 목록에 한정한 접근성 예외다.

## 시스템 영역

Figma PNG와 Simulator 캡처의 상태 표시·홈 인디케이터 렌더링 차이는 제품 UI 변경
판단에서 제외한다. 정량 비교에서는 상단 186 px, 하단 102 px를 마스킹했다.

## 픽셀 차이 해석

Medium Figma↔After의 mean absolute channel delta는 약 4.31이다. 다른 렌더러의
글꼴 안티앨리어싱, blur, shadow 차이가 남으므로 0을 목표로 하지 않는다. 구조,
기준선, 컴포넌트 크기와 기능 회귀를 함께 검토한다.
