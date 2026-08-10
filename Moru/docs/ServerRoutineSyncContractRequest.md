# 서버 루틴 동기화 계약 요청서

기준: [2026-08-10 live Swagger](https://moru-api.duckdns.org/v3/api-docs)

## 목적과 전제

iOS의 원본 데이터는 SwiftData입니다. 서버는 계정 백업·공유·통계용
projection이며, 서버가 표현하지 못하는 로컬 필드를 덮어쓰지 않습니다.

이 문서는 iOS가 루틴 write sender를 안전하게 켜기 전에 필요한 서버 계약입니다.
현재 앱은 로그인 중 CRUD intent를 영속 Outbox에 저장할 수 있지만, 모든 새
항목을 `waitingForServerContract`로 보관하고 서버 write를 호출하지 않습니다.
P0이 Swagger와 실서버에 배포되고 E2E로 검증되기 전까지 이 상태를 유지합니다.

용어는 반드시 아래처럼 구분합니다.

| iOS 로컬 | 서버 | 안정적인 client ID |
| --- | --- | --- |
| `Routine` | `RoutineGroup` | `Routine.id` (`clientEntityId`) |
| `RoutineStep` | `Routine` | `RoutineStep.id` (`clientEntityId`) |
| `RoutineStepResult` | `RoutineExecution` | `RoutineStepResult.id` (`clientExecutionId`) |
| 직접 대응 없음 | AI/TTS `RoutineStepResponse` | 없음 |

서버 `Routine`은 iOS의 `RoutineStep`입니다. AI/TTS의 작은 substep은 iOS
로컬 모델에 대응하지 않으므로, 제목·순서로 서버 ID를 추측해 연결하면 안 됩니다.

## P0 — write sender 활성화 전 필수

### 1. 모든 mutation의 멱등성

다음 모든 mutation이 `Idempotency-Key` HTTP header를 받습니다.

- `POST /routine-groups`
- `POST /routine-groups/{routineGroupId}/routines`
- `PATCH /routine-groups/{routineGroupId}/active`
- `DELETE /routine-groups/{routineGroupId}`
- `DELETE /routines/{routineId}`
- `POST /routine-executions`

요구 동작:

1. key 범위는 인증된 member와 mutation endpoint를 포함합니다.
2. 같은 key와 같은 canonical request payload는 최초 처리 결과(성공 또는
   결정된 오류)를 다시 반환합니다.
3. 같은 key와 다른 payload는 `409 Conflict`를 반환합니다.
4. DB 변경과 idempotency record 저장은 하나의 서버 transaction으로 처리합니다.
5. key는 최소 서비스 측 재시도/reconciliation 기간 동안 보존합니다.

iOS는 Outbox의 `generationID`를 미래의 `Idempotency-Key`로 사용합니다.

### 2. client ID를 받고 그대로 반환

그룹 생성과 자식 루틴 생성 request는 각각 `clientEntityId: UUID`를 받습니다.
응답은 받은 값을 변경하지 않고 포함합니다. 특히 그룹 생성 응답은 그룹과
그룹 안의 모든 자식에 대해 아래 쌍을 반환해야 합니다.

```json
{
  "routineGroupId": 123,
  "clientEntityId": "<local Routine.id>",
  "routines": [
    {
      "routineId": 456,
      "clientEntityId": "<local RoutineStep.id>"
    }
  ]
}
```

`POST /routine-executions`는 `clientExecutionId: UUID`를 받고 응답에도
그 값을 반환합니다. `clientExecutionId`는 member 범위에서 unique여야 하며,
같은 `RoutineStepResult.id`의 재저장은 새 `RoutineExecution` 행을 만들면 안
됩니다. 각 Outbox generation의 `Idempotency-Key`는 그 generation의 재전송만
보호하고, 더 최신 generation이 같은 `clientExecutionId`를 보내면 서버는
결과를 결정적으로 upsert/update해야 합니다. 같은 ID의 후속 변경을 허용하는
`POST` upsert 계약 또는 `PATCH /routine-executions/{routineExecutionId}`를
P0에 제공합니다. 어느 방식을 택해도 최신 확정 payload와 같은
`clientExecutionId`를 응답에 반환합니다.

iOS는 그룹 ID만 받았을 때 자식 ID를 제목·순서로 추측하지 않고 reconciliation
상태로 남깁니다.

### 3. timeout 뒤 결과를 찾는 reconciliation API

idempotency key로 이전 mutation의 처리 결과를 조회할 API가 필요합니다. 경로는
서버가 정해도 되지만, 예를 들어 다음처럼 동작해야 합니다.

```text
GET /routine-sync/mutations/{idempotencyKey}
```

- 인증된 같은 member만 조회할 수 있습니다.
- 아직 모르면 명확한 `pending`/`notFound` 상태를 반환합니다.
- 완료면 원 mutation과 동등한 result 및 모든 client ID ↔ server ID mapping을
  반환합니다.
- 실패면 재시도 가능 여부를 추측하지 않아도 되는 결정된 오류를 반환합니다.

### 4. 응답 schema의 필수성

성공 응답의 공통 `result`와 아래 식별자 필드는 OpenAPI에서 `required`로
선언합니다. optional/null처럼 표현되면 iOS는 안전하게 binding할 수 없습니다.

- `routineGroupId`, `routineId`, `routineExecutionId`
- 각 요청의 `clientEntityId` 또는 `clientExecutionId`
- 그룹 삭제의 `routineGroupId`
- 활성 변경의 활성/비활성 결과 ID

### 5. 재전송 안전한 삭제

자식 루틴 삭제의 실제 경로는 `DELETE /routines/{routineId}`입니다.
동일 member의 이미 삭제된 리소스를 같은 key로 다시 삭제해도 성공으로 수렴해야
합니다. 그룹 삭제 응답은 삭제된 `routineGroupId`를 반환합니다. 권한 없는
리소스는 존재 여부를 노출하지 않는 현재 보안 정책을 유지해도 됩니다.

### 6. 계정당 단일 활성 그룹

서버와 iOS 모두 한 계정에 활성 `RoutineGroup`을 최대 하나만 허용합니다.

- `isActive: true`는 기존 활성 그룹을 같은 서버 transaction에서 비활성화하고
  새 그룹 하나를 활성화합니다.
- 응답은 새 활성 `routineGroupId`와 비활성화된 ID 목록을 반환합니다.
- `isActive: false`는 활성 그룹이 0개인 상태를 허용합니다.
- `GET /routine-groups/active`는 활성 항목이 없을 때의 계약을 명시합니다.
  권장값은 성공 공통 응답의 `result: null`입니다.

## P1 — 편집·실행의 완전한 동기화 전

- 그룹 제목·설명·요일·시간·날씨 설정을 바꾸는 PATCH
- 자식 루틴 제목·타입·`duration`을 바꾸는 PATCH
- 순서 전체를 한 transaction으로 바꾸는 단계 재정렬 API
- 모든 편집 응답의 revision/ETag와 request `If-Match`; stale write는 `412`
- 실행 저장의 `completedAt`, `timeZone`, `clientExecutionId`
- AI 단계 판정은 저장 mutation이 없는 순수 RPC로 만들거나 별도
  `Idempotency-Key` 계약 제공

P1 전에는 해당 필드 변경과 재정렬을 로컬에서만 저장합니다. iOS는 이 제한을
삭제 후 재생성으로 우회하지 않습니다.

## P2 — TTS와 다기기 복구

### TTS

`GET /routine-tts/{routineGroupId}/tts` 또는 후속 TTS API는 다음을 명시합니다.

- URL 만료 시각과 인증 방식
- MIME type, checksum, cache key
- `PENDING` 재조회 권장 시각과 `FAILED` 오류 코드
- 음성 또는 루틴 내용 변경 때 새 cache key가 발급되는 규칙

### 다기기 복구

다른 기기에서 삭제·변경을 복구해야 할 때는 tombstone과 delta cursor API를
제공합니다. cursor의 범위, 만료, 정렬, account 격리와 삭제 항목의 보존 기간을
OpenAPI와 운영 정책에 명시합니다.

## P0 수용 및 E2E 기준

1. 같은 key/same payload를 timeout 뒤 재전송해도 그룹·자식·실행이 하나만
   만들어집니다.
2. 다른 generation이 같은 member의 `clientExecutionId`를 다시 저장하면
   기존 실행 한 행이 최신 payload로 결정적으로 갱신되고, 두 번째 실행 행이
   생기지 않습니다.
3. 같은 key/different payload는 `409`입니다.
4. 그룹 생성 응답만으로 모든 자식의 정확한 client ID ↔ server ID binding이
   가능합니다.
5. 응답이 유실된 요청은 reconciliation API로 결과와 mapping을 복구합니다.
6. 그룹·자식 삭제는 재전송해도 성공으로 수렴합니다.
7. 서로 다른 두 그룹 활성화 요청 뒤 서버에는 활성 그룹이 최대 하나이며,
   응답이 변경된 ID를 모두 설명합니다.
8. Swagger의 required schema와 실서버 응답이 일치함을 계약 테스트로 검증합니다.

이 기준을 통과한 뒤에만 iOS sender를 제한적으로 활성화합니다. 그 전에는
Outbox가 존재해도 서버 write 호출 수는 0이어야 합니다.
