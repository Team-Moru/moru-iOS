# P2 Home·Profile 디자인 QA

## 판정 기준

- Figma version: `2379679754802507594`
- Before: `main@02c43e4fb5d2a562659fe702f257350e8b7173e2`
- 환경: iPhone 16, 393 × 852 pt, 3x, Light, `ko_KR`, `Asia/Seoul`
- 상태: Home 7개 + Profile 7개, Medium/AX3
- 비교: source/implementation combined side-by-side, overlay, heatmap, metrics

## QA 반복

### Pass 1

- P1: Home header background이 layout participant가 되어 제목과 모든 카드가
  Figma보다 아래로 밀렸다.
  - 수정: glow를 `VStack.background`로 분리해 title y=261, cards y=379,
    weather y=583, current routine y=687의 Figma geometry를 맞췄다.
- P1: 기존 streak 불꽃의 36 × 36 px 1x source가 3x capture에서 흐렸다.
  - 수정: Figma `2394:2688`을 scale 3으로 export한 전용 asset을 사용했다.

### Pass 2

- P1: loading에서 header가 사라지고 generic progress view가 표시되어 Figma
  skeleton 구조와 달랐다.
  - 수정: cold loading도 동일 header를 유지하고 184/84/326 pt skeleton block을
    deterministic하게 렌더했다.
- P2: Profile voice section 간격과 row 사이 간격이 Figma보다 조밀했다.
  - 수정: section top 38 pt, content gap 16 pt로 조정했다.

### Pass 3

- P1: Profile long-Korean AX3에서 표시 이름이 두 줄 제한으로 생략됐다.
  - 수정: accessibility size에서는 line limit을 해제해 카드가 내용 높이로
    확장되고 이름 전체가 scroll 흐름 안에서 보이도록 했다.
- 수정 후 14상태 × Medium/AX3 × repeat를 다시 캡처해 byte-identical과
  영구 clipping 부재를 확인했다.

### Pass 4

- P2: 마이 탭에 선택 음성·알람 상태·서버 계정 요약이 함께 노출되어 최신
  Profile reference의 단순한 정보 구조와 달랐다.
  - 수정: `음성 설정`, `계정`, `데이터 관리`만 남기고, 음성 행에는
    `모루 말투`만 표시했다.
- P2: 비로그인 프로필이 `로컬 프로필`로 표시되고 계정 연결 화면이
  navigation sheet 형태라 reference의 연결 흐름과 달랐다.
  - 수정: splash MORU 마크와 `소셜 로그인`을 사용하고, Apple·Google·카카오
    인증 버튼을 피그마 형태의 bottom sheet에 배치했다. 연결 상태는
    `카카오 계정 연결됨`처럼 provider별로 표시한다.
- 수정 후 signed-out Profile 상태와 카카오 연결 Profile 상태를 iPhone 16,
  Light/Medium viewport에서 다시 캡처했다.

## 최종 평가

- Typography: Medium은 Figma size/weight/exact line-height, AX3는 자연
  line-height와 wrapping을 사용한다.
- Layout/spacing: Home 20 pt margins, 24 pt cards, 20 pt gap, 84 pt weather와
  326 pt current-routine block이 source geometry와 일치한다. Profile title,
  profile card, section hierarchy도 동일 rhythm을 따른다.
- Colors/surfaces: pilot canvas, orange accent, blue-gray text와 translucent white
  glass surface가 승인 token을 사용한다.
- Imagery/icons: streak 불꽃은 Figma scale 3 export다. tab과 설정 action은
  기존 design-system/SF Symbols를 사용하며 emoji·code-native 대체 이미지는 없다.
- Copy/content: `설정`, `음성 설정`, `모루 말투`, `계정`, `소셜 로그인`,
  `데이터 관리`, `로컬 데이터 초기화`를 확인했다. 연결된 계정은
  `~ 계정 연결됨` 형식을 사용한다.
- States/interactions: routine 시작·편집·생성, weather refresh, voice 선택·미리듣기,
  Apple·Google·카카오 계정 연결, 로그아웃·회원탈퇴, data reset 계약을 유지한다.
- Accessibility: AX3에서 content card는 높이로 확장되고 scroll로 접근 가능하다.
  semantic Button과 기존 accessibility identifier를 유지하고 glow는 숨겼다.

## Pixel gate

- Canonical Medium Figma/After MAE:
  - home regular `6.862129695698633`
  - home loading `5.5686025632779`
  - profile regular `4.382033294788926`
- 3개 canonical gate는 MAE ≤ `7`을 만족한다.
- 28개 Before/After metrics는 `comparedPixelCount == 2673972`,
  `maskedPixelCount == 339552`를 만족한다.
- Before/After MAE 범위
  `2.8407589907448543...24.840877042342502`는 layout, surface, type scale와
  AX3 reflow의 의도적 변경 ledger다.

## 자체 리뷰

- P0: 0
- P1: 0
- P2: 0

final result: passed
