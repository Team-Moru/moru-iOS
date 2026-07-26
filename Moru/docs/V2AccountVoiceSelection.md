# P7 계정 음성 목록·선택 계약

확인 기준은 2026-07-26 `https://moru-api.duckdns.org/v3/api-docs`다.

## 서버 계약

- `GET /tts`는 bearer 요청이며 `voices`의 `ttsId`, `voiceCode`, `displayName`,
  `description`, `proOnly`를 모두 검증한 뒤 계정별 SwiftData cache에 upsert한다.
- `PATCH /members/me/tts`는 bearer 요청이며 body는 `{"ttsId": Int64}`다.
- PATCH 응답의 `memberId`, `ttsId`, `voiceCode`가 요청 Outbox와 정확히 일치하고,
  authoritative 선택을 cache에 저장한 경우에만 Outbox executor가 `.sent`를 반환한다.
- transport, 408, 429, 5xx 재시도와 generation guard는 P6 Outbox 계약을 그대로 쓴다.

## 호환성과 fallback

- 서버 `voiceCode`와 `VoiceProfile`은 `VoiceCompatibilityTable`의 명시 항목으로만
  연결한다. `displayName`은 호환성 판단에 사용하지 않는다.
- Swagger에는 `MINSEO` 예시만 있고 번들 asset code와의 호환 관계가 없다.
  따라서 production 호환표는 현재 비어 있다.
- 호환표 밖 서버 음성, PRO 음성, 알 수 없는 metadata, 번들 음원이 없는 음성은
  목록에 표시하되 선택과 preview를 비활성화한다.
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

## 불일치 처리

- PATCH authoritative success는 계정 cache에 마지막 서버 선택으로 기록한다.
- 이후 로그아웃 중 로컬 선택이 달라진 뒤 같은 계정으로 돌아오면 자동 덮어쓰지 않고
  `기기 음성 유지` 또는 `서버 음성 사용`을 사용자가 선택한다.
- 현재 GET `/tts`는 서버의 현재 선택을 제공하지 않으므로 최초 로그인 직후 불일치는
  판정할 수 없다. 별도 read contract가 생기기 전까지 이 한계를 유지한다.

## 제외

- 서버 음원 생성, 상태 조회, 다운로드, cache와 RoutinePlayer 연결
- 표시 이름 자동 매핑
- Routine/Run sync
- AI 추천
