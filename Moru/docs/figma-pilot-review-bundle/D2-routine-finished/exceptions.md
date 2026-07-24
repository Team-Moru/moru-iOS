# D2 의도적 예외와 남은 차이

## README 우선 예외

- Figma `2644:2839`의 trial CTA 문구는 `계정 생성하기`다.
- 최신 README의 v1 계약은 local-only session이며 auth 흐름이 아니다.
- 새 계정 생성 navigation을 만들지 않고 기존 `onTapHome` summary exit callback과
  `홈으로` 문구를 유지했다.

## 상태 범위

- Figma는 regular Medium `1656:1043`, trial Medium `2644:2839`만 제공한다.
- streak 없음, 완료 단계 없음, 긴 한국어 단계와 AX3는 기존 기능을 유지하면서
  같은 pilot token과 responsive layout을 적용했다.
- AX3는 140% token line-height를 Dynamic Type로 scale한 결과 콘텐츠가 더 길어질
  수 있으므로, 모든 내용을 한 viewport에 압축하지 않고 기존 ScrollView로 제공한다.
- 완료 단계가 없을 때의 기존 문구 `완료한 루틴이 없습니다.`는 Figma에 없는 상태라
  새 card나 illustration을 만들지 않았다.

## 데이터 표시

- Figma streak card는 현재 연속 일수만 표시한다.
- 기존 `bestDays` 계산과 모델은 변경하지 않았고 VoiceOver label에서 최고 기록을
  계속 제공한다.

## 비교 조건

- status bar와 home indicator는 앱 구현 대상이 아니므로 comparator에서 위 186 px,
  아래 102 px를 마스킹했다.
- Simulator의 font anti-aliasing, SwiftUI radial stroke, asset compositing 차이로
  0-diff를 목표로 하지 않는다.
- regular Figma↔After mean absolute channel delta는 `9.9783`, trial은 `7.9229`다.

## Canonical Before

- Before는 D0 review fix와 D1 merge를 모두 포함한
  `main@9e89776e1fa4dc075423bddd7ba2b45899a953d4`의 detached clean worktree에서
  다시 캡처했다.
- 캡처 전용 fixture만 임시로 복사했으며 base 앱 소스와 project file은 수정하지 않았다.
