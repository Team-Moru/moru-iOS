# P1 Splash·온보딩 디자인 QA

## 판정 기준

- Figma version: `2379679754802507594`
- Before: `main@d5104a1c26aa23fcc2a05298e7ebd292ac116fb1`
- 환경: iPhone 16, 393 × 852 pt, 3x, Light, `ko_KR`, `Asia/Seoul`
- 상태: 13개, Medium/AX3
- 비교: source/implementation/combined side-by-side, overlay, heatmap, metrics

## QA 반복

### Pass 1

- P0: AX3 exact line-height와 고정 footer에서 progress, 제목, CTA 글리프가
  잘리거나 겹쳤다.
  - 수정: 접근성 크기에서 자연 line-height를 사용하고 progress/고정 CTA에
    안전 상한을 적용했다.
- P1: organizing에 progress header가 남고 completion은 code-native badge를 사용했다.
  - 수정: 두 장면을 전용 full-height layout으로 분리하고 기존 Figma 일치 asset을 썼다.
- P1: alarm에 Figma sample의 비구현 사운드 surface가 남고 voice에는 asset code가
  설명으로 노출됐다.
  - 수정: 비구현 surface를 제거하고 번들 음성 4종의 고정 한국어 설명을 적용했다.

### Pass 2

- P2: combined experience 비교에서 공통 본문 시작이 Figma보다 약 13 pt 위였고
  첫 card 간격도 짧았다.
  - 수정: content top inset을 20→32 pt, experience title/content gap을 56→68 pt로
    조정했다.
- 수정 후 experience title과 첫 card 시작은 source와 약 1 pt 이내로 정렬됐고
  MAE는 `10.15489740854928`→`8.486838680434948`로 개선됐다.

### Pass 3

- P1: 기존 visual regression fixture를 직접 검토하자 AX3에서 고정 footer CTA가
  accessibility1 크기에도 가로로 잘렸다.
  - 수정: 고정 54 pt CTA의 글꼴을 Medium으로 유지하고 한 줄·축소 안전장치를
    적용했다. 본문은 AX3 확대와 scroll 접근성을 그대로 유지한다.
- 수정 후 voice AX3 CTA 전체 문구가 viewport 안에 노출되는 것을 새 capture와
  `FinalScreenVisualTests` 승인 hash에서 직접 확인했다.

## 최종 평가

- Typography: Medium은 Pretendard size/weight/exact line-height, AX3는 자연
  line-height로 읽기 흐름과 wrapping을 유지한다.
- Layout/spacing: 20 pt margins, progress, 32 pt content start, card/CTA radius와
  vertical hierarchy가 source와 일치한다.
- Colors/surfaces: pilot canvas, orange accent, blue-gray text/border와 white cards가
  승인 token을 사용한다.
- Imagery/icons: Splash brand와 duration clock은 Figma export, organizing orb와
  completion badge는 기존 일치 asset이다. code-native 대체 이미지는 없다.
- Copy/content: 고정 경험·목표·음성 copy를 확인했다. 로컬 데이터와 기능 사실이
  Figma sample보다 우선한다.
- States/interactions: experience 선택, 목표 multi-select, freeform, editable review,
  alarm 증감/요일, 음성 미리듣기, 저장과 completion callback 계약을 유지한다.
- Accessibility: Medium/AX3 13상태에 영구 clipping/overlap이 없고 본문은 scroll로
  접근 가능하다. 버튼은 semantic Button과 기존 accessibility identifier를 유지한다.

## Pixel gate

- Canonical Medium Figma/After MAE:
  - splash `7.26837752975723`
  - experience `8.486838680434948`
  - goals `11.542955074573207`
  - suggested-routine `11.496891266375764`
  - duration `11.136655881213416`
  - freeform `10.566077605400007`
  - organizing `8.98087526720549`
  - review `11.474923821191846`
  - voice `11.29483554801621`
  - completion `8.264485068155787`
- 위 10장 gate는 MAE ≤ `12`를 만족한다.
- 기능 보존 alarm은 MAE `17.311831238322615`이며 정적 장식 대신 조작 가능한
  wheel, 금지 surface 제거에 따른 승인 예외다.
- 26개 Before/After metrics는 `comparedPixelCount == 2673972`,
  `maskedPixelCount == 339552`, `maximumChannelDelta <= 227`을 만족한다.
- Before/After MAE 범위 `5.586668446790019...32.33005132439681`은 Splash asset,
  layout, type scale와 AX3 reflow의 의도적 변경 ledger다.

## 자체 리뷰

- P0: 0
- P1: 0
- P2: 0

final result: passed
