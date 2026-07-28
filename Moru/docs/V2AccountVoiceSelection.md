# P7 계정 음성 목록·선택 계약

확인 기준은 2026-07-26 `https://moru-api.duckdns.org/v3/api-docs`다.

## 서버 계약

- `GET /tts`는 bearer 요청이며 `voices`의 `ttsId`, `voiceCode`, `displayName`,
  `description`, `proOnly`를 모두 검증한 뒤 계정별 SwiftData cache를 원자적으로
  교체한다. 빈 성공 응답도 authoritative empty catalogue로 취급해 stale catalogue
  row를 제거한다. 단, PATCH가 방금 반환한 authoritative conflict는 catalogue와
  별도 의미의 conflict-only row로 보존해 GET 목록에 없더라도 사용자 결정을
  받기 전에 사라지지 않게 한다.
- GET에 같은 `voiceCode`가 새 `ttsId`로 제공되면 code를 안정 identity로 보고
  catalogue의 새 ID로 authoritative metadata를 갱신한다. PATCH도 같은 로컬 음성을
  나타내는 canonical ID 변경은 성공으로 수용한다.
- `PATCH /members/me/tts`는 bearer 요청이며 body는 `{"ttsId": Int64}`다.
- PATCH 응답의 `memberId`가 요청 계정과 다르면 응답을 폐기한다. 같은 계정의 응답은
  authoritative 선택으로 cache에 기록한다. 응답 `voiceCode`가 호환표에서 사용자가
  선택한 동일 로컬 음성을 뜻하면 서버의 canonical `ttsId`·code alias를 수용하고
  executor가 `.sent`를 반환한다. 다른 로컬 음성을 뜻하거나 호환할 수 없는 선택이면
  명시적 불일치로 보존하고 mutation은 자동 재시도하지 않는다.
- GET과 PATCH는 요청 시작 때 `memberID`와 in-memory account session generation을
  함께 고정한다. 성공·실패 응답 전에 generation을 다시 검증해 로그아웃 뒤 다른
  계정 token으로 요청을 보내거나 stale 응답을 반영하지 않는다.
- transport, 408, 429, 5xx 재시도와 generation guard는 P6 Outbox 계약을 그대로 쓴다.

## 호환성과 fallback

- 서버 `voiceCode`와 `VoiceProfile`은 `VoiceCompatibilityTable`의 명시 항목으로만
  연결한다. `displayName`은 호환성 판단에 사용하지 않는다.
- Swagger에는 `MINSEO` 예시만 있고 번들 asset code와의 호환 관계가 없다.
  따라서 production 호환표는 현재 비어 있다.
- 호환표 밖 서버 음성, PRO 음성, 알 수 없는 metadata, 번들 음원이 없는 음성은
  목록에 표시하되 선택과 preview를 비활성화한다.
- 서버 목록을 정상 수신해도 선택 가능한 서버 매핑으로 대표되지 않은 앱 내장 음성은
  계속 표시한다. 따라서 production 호환표가 비어 있어도 기존 로컬 음성 선택 기능은
  사라지지 않는다.
- 서버 목록 요청이 실패하면 해당 계정 cache를 사용한다. cache도 비어 있으면 기존
  `VoiceProfile.localVoices`를 그대로 표시한다.
- 로그아웃 중에는 기존 로컬 선택과 번들 preview만 사용하며 계정 Outbox를 만들지 않는다.

## Local-first와 Outbox

- 선택 가능한 서버 음성은 LocalProfile에 먼저 저장한다.
- 그 뒤 `account.voice.selection` operation key로 payload version 1을 coalescing enqueue한다.
- payload는 `version`, `memberID`, `ttsID`, `voiceCode`, `localVoiceID`만 포함한다.
- enqueue 또는 서버 전송 실패는 이미 저장한 LocalProfile 선택을 되돌리지 않는다.
- P6 idempotency key가 바뀐 뒤 이전 in-flight success/failure는 새 generation을
  삭제하거나 backoff할 수 없다.
- 로그아웃과 회원 탈퇴는 해당 계정의 in-flight 동기화를 먼저 취소·drain하고 새
  동기화를 정지한다. 로그인 성공 또는 유효한 session 복원 뒤에만 다시 허용하고
  남아 있는 Outbox를 drain한다.

## 불일치 처리

- PATCH authoritative success는 계정 cache에 마지막 서버 선택으로 기록한다.
- 이후 로그아웃 중 로컬 선택이 달라진 뒤 같은 계정으로 돌아오면 자동 덮어쓰지 않고
  `기기 음성 유지` 또는 `서버 음성 사용`을 사용자가 선택한다.
- authoritative 서버 음성이 PRO 전용, 호환표 밖, 알 수 없는 metadata, 번들 누락
  상태여도 불일치를 숨기지 않는다. 이때 사용할 수 없는 `서버 음성 사용` 선택지는
  노출하지 않고 기기 음성 유지 경로만 제공한다. 기기 음성에 대응하는 선택 가능한
  서버 항목도 없으면 사용자의 명시적 선택을 계정 cache에 acknowledgement로 남겨
  같은 해결 불가능한 dialog를 반복하지 않는다.
- 현재 GET `/tts`는 서버의 현재 선택을 제공하지 않으므로 최초 로그인 직후 불일치는
  판정할 수 없다. 별도 read contract가 생기기 전까지 이 한계를 유지한다.

## 제외

- 서버 음원 생성, 상태 조회, 다운로드, cache와 RoutinePlayer 연결
- 표시 이름 자동 매핑
- Routine/Run sync
- AI 추천
