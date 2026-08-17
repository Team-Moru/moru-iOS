# 루틴 동기화 공통 기반

## 데이터 원본

```text
SwiftData가 루틴과 실행 기록의 원본이다.
서버는 로그인 계정의 백업·공유·통계용 projection이다.
서버 장애나 로그아웃은 로컬 루틴 실행을 막지 않는다.
```

서버 응답을 편집 가능한 로컬 상태로 바로 표시하지 않습니다. 먼저 DTO를
검증하고 account-scoped binding과 충돌 정책을 거쳐 SwiftData에 반영합니다.
서버 projection은 로컬의 모든 필드를 표현하지 못하므로, 서버 값이 로컬의
원본을 덮어쓰는 완전 동기화가 아닙니다.

## 서버 projection 범위

현재 서버는 로컬 필드 전부를 받지 않으므로 완전한 복사본은 아닙니다.

## 로컬과 서버의 이름 대응

| 로컬 | 서버 | stable client ID |
| --- | --- | --- |
| `Routine` | `RoutineGroup` | `Routine.id` |
| `RoutineStep` | `Routine` | `RoutineStep.id` |
| `RoutineRun` | 직접 대응 없음 | `RoutineRun.id` |
| `RoutineStepResult` | `RoutineExecution` | `RoutineStepResult.id` |
| 직접 대응 없음 | AI/TTS의 `RoutineStepResponse` | 없음 |

서버의 `Routine`은 로컬의 `RoutineStep`입니다. 서버 응답의 더 작은 AI/TTS
`RoutineStepResponse`에는 로컬 대응 모델이 없습니다. 둘을 같은 step으로
취급하면 안 됩니다. 현재 요청으로 보내지 못하는 로컬 필드는
`goalTags`, `instruction`, `isRequired`, `presetItemID`, 알람 소리,
`includeFortune`, 명시적인 단계 순서입니다.

## ID 모델

`PersistedRoutineServerBinding`은 다음 세 ID를 분리합니다.

| ID | 의미 |
| --- | --- |
| `localEntityID` | 기존 Routine, RoutineStep, RoutineRun 등의 로컬 UUID |
| `clientEntityID` | 기존 `localEntityID`를 그대로 쓰는 안정적인 client UUID |
| `remoteID` | 현재 서버가 발급하는 account-scoped `Int64` ID |

binding 자연키는 `server namespace + memberID + entity kind + localEntityID`입니다.
역방향 키는 `server namespace + memberID + entity kind + remoteID`입니다.
같은 로컬 루틴을 여러 계정이나 운영/스테이징 서버에서 사용해도 ID가 섞이지
않습니다. 한번 연결된 remote ID를 다른 값으로 조용히 덮어쓰지 않고
conflict로 처리합니다.

그룹 생성 응답에서 그룹 ID와 자식 routine ID들을 얻으면
`recordRemoteIDs`로 모두 검증한 뒤 한 번에 저장합니다. 한 쌍이라도 앞/뒤
방향으로 충돌하면 어떤 새 binding도 저장하지 않습니다.

기존 `Routine.sync.remoteID` 문자열에는 account ID나 여러 서버 ID를 합쳐
넣지 않습니다. v1 `localOnly` 모델과 서버 연결 정보를 분리합니다.

## Outbox와 로컬 중복 방지

`PersistedRoutineSyncMutation`은 typed `RoutineSyncCommand`의 버전 있는
payload를 보관합니다. 그룹 생성, 자식 루틴 추가, 활성 그룹 선택/해제,
그룹·자식 삭제, 실행 결과 저장만 command가 됩니다. 일반 편집과 재정렬은
현재 서버가 표현하지 못하므로 로컬 저장만 합니다.

엔터티 command는 다음 자연키로 변경을 하나만 보관합니다.

```text
server namespace + memberID + operation + entity kind + localEntityID
```

활성 선택은 엔터티별 command가 아니라 계정별 `activeSelection` 하나만
보관하고, 가장 최신 선택으로 coalesce합니다.

- 같은 canonical JSON payload 재등록: 기존 mutation과 로컬 `generationID` 재사용
- 다른 payload 재등록: 최신 값으로 coalesce, generation 증가,
  `generationID` 교체
- payload는 `payloadVersion`과 함께 저장해 앱 업데이트 후 안전하게 해석
- 오래된 요청 결과: expected `generationID`가 다르면 무시
- 응답이 성공했는지 알 수 없음: `needsReconciliation`
- `attempting`은 보낼 generation/payload/시각을 영속 snapshot으로 남긴다.
  앱이 그 상태에서 종료되면 다음 시작에서 `needsReconciliation`으로 바꾼다.

저장소가 JSON key를 정렬해 같은 뜻의 body를 같은 byte로 만듭니다. 이 동작은
기기 안의 중복과 늦게 도착한 결과만 막습니다. 서버 중복 생성까지 막는
보장은 아닙니다.

## 현재 API에서 지키는 안전 경계

운영 P0 계약은 `clientEntityId`, `Idempotency-Key`, 생성 응답의 local/remote
ID 매핑, replay-safe delete를 지원합니다. 새 Outbox 항목은
`waitingForServerContract`로 시작하고, production contract가 지원하는 operation만
sender가 `queued`로 승격합니다.

| 현재 API | Outbox의 local ID | 현재 자동 전송 |
| --- | --- | --- |
| `POST /routine-groups` | `Routine.id` | 전송 |
| `POST /routine-groups/{id}/routines` | `RoutineStep.id` | 전송 |
| `PATCH /routine-groups/{id}/active` | `Routine.id` | 의미 확인 전 차단 |
| `DELETE /routine-groups/{id}` | `Routine.id` | 전송 |
| `DELETE /routines/{routineId}` | `RoutineStep.id` | 전송 |
| `POST /routine-executions` | `RoutineStepResult.id` | 전송 |

`POST /routine-executions/ai-step`은 즉시 답을 받아야 하는 RPC라 Outbox에
넣지 않습니다. TTS 조회도 읽기 API이므로 mutation이 아닙니다.

아래 POST가 timeout, 5xx, 응답 decode 실패처럼 성공 여부가 모호한 결과를
받으면, sender는 최초 시도 전에 영속화한 wire bytes와 generation UUID를
24시간 replay window 안에서 그대로 재사용합니다.

- `POST /routine-groups`
- `POST /routine-groups/{routineGroupId}/routines`
- `POST /routine-executions`

서버가 첫 요청을 처리한 뒤 응답만 유실했더라도 동일 `Idempotency-Key`와 동일
body로만 재전송되므로 새 요청 identity를 만들지 않습니다.

제목이나 순서 비교로 remote ID를 추측해 연결하지 않습니다. 특히 그룹 생성
응답에서 그룹 ID만 검증되면 그룹 binding만 저장합니다. 자식 ID가
`clientEntityID`와 함께 검증되지 않으면 그 mutation은
`needsReconciliation`으로 남깁니다.

현재 앱은 CRUD intent, contract-gated sender, production HTTP transport,
foreground account-bound runtime을 연결합니다. 로그인 세션별 local group
backfill도 sender보다 먼저 실행됩니다. 요청 중 계정 session generation이 바뀌면
기존 응답은 binding이나 Outbox를 정리하지 않습니다.

`RoutineSyncServerContract`는 operation별 필수 capability와 `isE2EVerified`를
동시에 확인합니다. 조건을 만족한 row만 `waitingForServerContract`에서 `queued`로
승격하며, `RoutineSyncSender`는 Outbox `generationID`를 그대로
`Idempotency-Key`로 사용합니다.

## 트랜잭션 경계

- 로그인 중 CRUD는 로컬 변경과 command stage를 같은 `ModelContext`에서 만든
  뒤 한 번만 저장합니다. Outbox 저장이 실패하면 로컬 변경도 저장하지 않습니다.
- 로그아웃 상태에서는 Outbox를 만들지 않습니다. 계정 세션이 확정되면 아직 해당
  회원의 binding이 없는 `localOnly` 그룹을 현재 snapshot으로 Outbox에 backfill한
  뒤 활성 그룹 선택 intent를 로컬 우선순위에 맞춰 등록하고 sender를
  시작합니다. 동일 snapshot의 재등록은 기존 generation UUID를 재사용합니다.
- 서버 응답으로 생성 성공을 확정할 때는 검증된 binding과 해당 Outbox 정리를
  한 번의 save로 처리합니다. 삭제 성공은 삭제 대상 binding과 Outbox를 함께
  지웁니다.
- 그룹 삭제는 그룹과 그 자식 routine binding을 지우되, 과거 실행 기록 binding은
  보존합니다.
- 현재 루틴 저장은 sender 상태와 무관하게 로컬에서 정상 동작합니다.
- 이름·시간·요일·알람·날씨·기존 단계 내용 수정과 재정렬은 현재 API가 표현하지
  못합니다. 이를 삭제 후 재생성으로 흉내 내면 ID, 기록, TTS 연결이 깨지므로
  Outbox command를 만들지 않습니다.

## 활성 루틴 규칙

한 계정에서 활성 `Routine`은 최대 하나이며, 전부 비활성인 상태도 허용합니다.
새 활성화는 확인 후 기존 활성 루틴 전체를 비활성화하고 해당 알람도 끈 뒤
새 루틴 하나만 활성화합니다. 기존 요일 설정은 그대로 보존합니다.

기존 데이터에 여러 활성 루틴이 있으면 `updatedAt`이 가장 최신인 루틴을
유지합니다. 동률이면 `createdAt`, 마지막으로 UUID의 결정적 순서로 고릅니다.
나머지는 비활성화하고 기존 플랫폼 알람도 취소합니다. 알람 취소 실패는 기존
alarm repair 경로에 남깁니다.

## 계정 수명

- 로그아웃: 로컬 데이터, binding, Outbox 보존
- 같은 계정 재로그인: 기존 binding과 stable client ID 재사용
- 회원 탈퇴: `(server namespace, memberID)` pending-cleanup marker는 아래
  phase를 영속한다.
  - `prepared`: 서버 호출 전의 로컬 의도일 뿐이다. 탈퇴 성공의 증거가 아니므로
    앱 시작 시 계정 데이터나 세션을 삭제하지 않는다.
  - `attempting`: 서버 호출 직전에 저장한다. timeout·transport 오류·프로세스
    종료 뒤에는 탈퇴 성공 여부가 모호하다. 이 marker도 자동 cleanup의 근거가
    아니며, 같은 member의 세션 복원만 보류한다. 다른 member의 새 세션은 막지
    않는다.
  - `remoteConfirmed`: 탈퇴 성공 응답을 받은 상태다. 이 경우에만 다음 앱 시작이
    binding·Outbox를 account-scoped transaction으로 지우고 marker를
    `localDataCleaned`로 전이한다. marker 자체는 이 transaction에서 삭제하지
    않는다.
  - `localDataCleaned`: 로컬 sync 데이터는 지웠지만 matching Keychain 세션을
    아직 지우지 못한 crash window다. 시작 시 세션을 제거한 뒤 marker를
    finalization한다.
  - `cancelled`: definitive 4xx 거절처럼 서버가 탈퇴를 commit하지 않았음이
    확실한 상태다. 계정 데이터는 보존하고 marker만 버린다.
  서버 성공 뒤 로컬 정리 실패는 `remoteConfirmed`를 보존한다. 반대로
  `prepared`/`attempting` 상태만으로는 sync 데이터나 session을 삭제하지 않는다.
- 전체 데이터 초기화: 모든 binding, Outbox, pending-cleanup marker 삭제
- 다른 계정 데이터: 보존

Outbox payload에는 루틴 제목이나 사용자의 입력이 포함될 수 있습니다. payload를
로그에 남기지 않고, 회원 탈퇴와 전체 초기화 때 위 규칙대로 삭제합니다.

## 후속 연동 조건

자동 전송과 재시도는 [서버 루틴 동기화 계약 요청서](ServerRoutineSyncContractRequest.md)의
P0이 Swagger와 실서버에 반영되고 E2E로 검증된 뒤에만 활성화합니다.
핵심은 `Idempotency-Key`, stable client ID 반환, timeout 뒤 reconciliation,
재전송 안전한 삭제, 단일 활성의 원자적 서버 계약입니다.

### sender 활성화 전 iOS P0 상태

완료:

- `createRoutineGroup` 또는 `addRoutine`이 `attempting`/`needsReconciliation`
  인 동안 로컬 그룹·자식을 삭제해도 로컬 변경을 rollback하지 않는다. 선행
  mutation은 그대로 보존하고 delete를 dependency-blocked successor로 기록한다.
- partial group-only mapping 뒤에도 최신 desired child graph를 create mutation의
  새 generation에 보존한다. attempted snapshot은 덮지 않으며, 검증된 mapping이
  도착하면 add/delete successor로 해석한다.
- create → add/active → execution → delete 순서는 binding과 선행 Outbox 존재 여부로
  admission한다. 서버 capability와 E2E 검증 플래그가 완전하지 않으면 어떤 row도
  `queued`가 되지 않는다.
- sender core는 claim 전에 exact generation을 고정하고, 모호한 transport 결과를
  `needsReconciliation`로 보내며 자동 재시도하지 않는다. reconciliation이
  미커밋을 증명한 경우에만 같은 generation을 다시 admission할 수 있다.

남음:

- P0이 배포된 Swagger DTO와 HTTP header를 구현하는 production transport
- idempotency key reconciliation endpoint adapter
- 실서버 E2E suite의 통과 결과를 production contract로 공급하는 release gate
- foreground/network 회복 시 한 번씩 sender를 실행하는 trigger와 계정 변경 E2E

위 항목과 서버 P0가 모두 완료되기 전에는 production sender를 활성화하지 않는다.
