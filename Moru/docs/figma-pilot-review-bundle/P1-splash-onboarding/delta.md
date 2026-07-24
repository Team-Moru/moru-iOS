# P1 변경 기록

## 구조·시각

- bootstrap과 navigation은 그대로 두고 idle/loading surface만 Figma Splash asset으로
  교체했다.
- 온보딩 progress를 실제 사용자 단계 1~8에 맞췄다. organizing은 전환 장면,
  completion은 완료 장면이므로 progress header를 노출하지 않는다.
- 20 pt horizontal inset, 32 pt content top inset, Figma progress bar, 54 pt pill CTA,
  blue canvas와 white surface를 적용했다.
- organizing과 completion은 header 없는 전용 중앙 layout으로 분리했다.
- Figma export의 Splash brand와 15분 clock asset, 기존 정리 orb와 완료 badge를
  그대로 사용했다.

## 문구·데이터

- 경험 설명 3개와 목표 설명 4개를 고정 feature copy로 분리했다.
- 음성 4종은 한국어 성격 설명을 표시하고 선택 음성 이름으로 CTA를 만든다.
- 추천 step 수와 예상 시간은 Figma sample을 복제하지 않고 로컬 routine의 실제 값을
  계산한다.
- freeform/organizing 문구는 AI 대신 로컬 템플릿 사실을 명시한다.

## 접근성·상태

- Medium은 Pretendard exact line-height를 유지한다.
- AX3는 온보딩 화면에만 자연 line-height를 적용하고 목표 grid를 1열로 reflow한다.
- 고정 progress 보조 숫자와 54 pt footer CTA는 Medium을 유지해 AX3에서도
  viewport 밖으로 잘리지 않게 했다. 본문은 AX3 크기와 ScrollView 접근성을 유지한다.
- long-korean, preview-unavailable, selected/disabled CTA를 결정론적으로 캡처했다.
