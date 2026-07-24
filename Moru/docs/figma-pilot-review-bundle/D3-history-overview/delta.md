# D3 이력 Overview 델타

## 구조

- title 아래의 기존 단일 streak card를 streak와 주간 완료 상태를 함께 보여주는
  pilot card로 바꿨다.
- Overview의 첫 viewport를 streak/weekly card, 기상 시간 패턴, 월간 히트맵 순서로
  재배치했다.
- 기존 이번 주 완수율과 최근 기록은 heatmap 아래의 scroll content로 유지했다.
- 주간 리포트, 날짜 상세, 최근 기록 navigation과 callback은 그대로 유지했다.

## 간격과 크기

- iPhone 16 Medium에서 header는 54 pt, horizontal inset은 20 pt다.
- streak/weekly card는 353 × 114 pt, radius 24 pt이고 위아래 8 pt 여백을 둔다.
- Overview section 사이 간격은 32 pt다.
- 기상 card는 353 × 111 pt, heatmap card는 353 pt 폭과 radius 24 pt를 사용한다.
- tab chrome은 safe area를 포함해 Figma의 95 pt 높이와 346 pt item row에 맞춘다.

## 타이포그래피와 색상

- title은 H3 24/33.6 semibold, section header는 B4 16/22.4 semibold다.
- streak 값과 기상 지표는 H1 32/44.8 bold를 사용한다.
- canvas `#F3F6FC`, accent `#FF9861`, inactive week `#D8E3FF`,
  heatmap `#FFEBE0` → `#FF9861` scale을 적용했다.
- 기상·heatmap card는 white 20% glass surface와 Figma의 `#D8E3FF`,
  radius 15 shadow를 사용한다.

## Skeleton과 상태 안전성

- loading spinner를 `2562:3611`의 card/header geometry와 동일한 deterministic
  linear-gradient skeleton으로 교체했다.
- empty와 failure는 vertical scroll container에서 중앙 정렬하며 AX3에서도
  메시지와 재시도 CTA까지 순서대로 접근할 수 있다.
- AX3에서 streak/weekly card는 세로로 reflow하고 weekday는 adaptive grid로 바뀐다.
- AX3 heatmap cell은 44 pt로 확대하고 텍스트 축소 하한을 두어 숫자 잘림을 막는다.
- D0의 exact line-height는 Medium에서 유지하고, History Overview의 AX3에만
  자연 line-height fallback을 적용해 제목, 지표, weekday와 retry CTA의 잘림을 막는다.

## 계산·데이터 계약

- streak, weekly, wake regularity, heatmap bucket 계산은 변경하지 않았다.
- ViewModel, Domain, Data, Repository, SwiftData 계약은 변경하지 않았다.
- test fixture는 자동 load를 끌 수 있는 기본값 `true`의 내부 init option만 사용한다.
