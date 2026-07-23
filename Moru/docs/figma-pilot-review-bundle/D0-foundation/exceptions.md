# D0 의도적 예외와 남은 위험

## 의도적 예외

- D0는 feature 화면 배치를 바꾸지 않습니다. Figma 원본은 다섯 component
  set을 각각 scale 3으로 export했습니다. 393×852pt component board와 직접
  늘이지 않았습니다.
- Figma/After의 화면 단위 pixel 판정은 D1 루틴 목록, D2 완료 화면,
  D3 이력 Overview에서 수행합니다.
- D0 component board에는 iOS 상태바와 home indicator가 없으므로 evidence 비교의
  mask는 0입니다. 비교 도구는 실제 화면용 top/bottom pixel mask를 지원합니다.
- 기존 `AppFont`와 공용 컴포넌트 기본 initializer는 전역 교체하지
  않았습니다.
  새 스타일은 `componentStyle: .figmaPilot`을 전달할 때만 적용됩니다.
- shadow `#D8E3FF`는 기존 `babyBlue150`의 `#D9E3FF`와 1 channel step이 달라
  별도 exact alias로 정의했습니다.

## 남은 위험

- AppKit PNG decode/encode 결과는 macOS sRGB pipeline을 전제로 합니다.
- `.ultraThinMaterial`의 실제 framebuffer는 simulator/OS build에 따라
  미세한 noise가 생길 수 있습니다. 화면 PR에서는 metric과 육안 검토를 함께
  사용합니다.
- AX3 component board는 scroll 가능한 첫 viewport를 캡처합니다. D1~D3에서는
  CTA 도달, 의미 순서와 실제 feature scroll을 별도 확인해야 합니다.
