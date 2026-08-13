# P2 의도적 예외

- Figma weather의 `서울특별시`, 최고·최저 기온은 현재 weather model에 없으므로
  추가하거나 하드코딩하지 않았다. 실제 상태, 온도, 갱신 시각과 refresh를 표시한다.
- Figma Home의 `8/8`, routine 이름, 날씨와 streak 수치는 sample이다.
  After는 fixture 및 실제 model이 제공하는 값을 사용한다.
- cold loading과 profile 없는 failure에서는 아직 사용자 이름을 읽을 수 없으므로
  Figma sample의 `모루님`을 하드코딩하지 않고 일반 인사만 표시한다.
- 소셜 로그인은 현재 앱에 구성된 Apple·Google·카카오 인증 흐름을 사용한다.
  Google 또는 카카오의 공개 설정이 없는 빌드에서는 해당 provider 버튼이
  비활성화될 수 있다.
- Figma Profile sample의 `Apple로 로그인` 표기는 provider별
  `계정 연결됨`으로 바꿨다. 비로그인 상태에서는 `소셜 로그인`만 표시한다.
- 기존 알람 상태·조치와 서버 계정 요약/보관함은 이번 마이 탭 정보 구조에서
  숨기고, 로컬 음성 선택과 계정 lifecycle·데이터 초기화 기능은 유지한다.
- Figma에 없는 empty, failure, partial data, 위치 권한 거부, fallback voice,
  alarm permission off, reset unavailable 상태는 기존 기능과 공통 token으로
  표현하고 상태별 capture로 검증했다.
- 상태바와 home indicator는 XCTest hierarchy render에 없으므로 비교에서
  상단 186 px, 하단 102 px를 마스킹했다.
