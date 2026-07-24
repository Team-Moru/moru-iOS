# P2 의도적 예외

- Figma weather의 `서울특별시`, 최고·최저 기온은 현재 weather model에 없으므로
  추가하거나 하드코딩하지 않았다. 실제 상태, 온도, 갱신 시각과 refresh를 표시한다.
- Figma Home의 `8/8`, routine 이름, 날씨와 streak 수치는 sample이다.
  After는 fixture 및 실제 model이 제공하는 값을 사용한다.
- cold loading과 profile 없는 failure에서는 아직 사용자 이름을 읽을 수 없으므로
  Figma sample의 `모루님`을 하드코딩하지 않고 일반 인사만 표시한다.
- Figma Profile의 Apple 로그인, 로그아웃, 회원탈퇴는 로컬 전용 v1 범위와
  충돌하므로 추가하지 않았다. 로컬 프로필 편집, 번들 음성, 알람, 초기화는 유지했다.
- Figma Profile sample의 계정 카드 부제는 `Apple로 로그인`이지만 실제 앱은
  `로컬 프로필`로 표시한다.
- Figma에 없는 empty, failure, partial data, 위치 권한 거부, fallback voice,
  alarm permission off, reset unavailable 상태는 기존 기능과 공통 token으로
  표현하고 상태별 capture로 검증했다.
- 상태바와 home indicator는 XCTest hierarchy render에 없으므로 비교에서
  상단 186 px, 하단 102 px를 마스킹했다.
