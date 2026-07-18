# MORU v1 Alarm Topology ADR

- Status: Accepted
- Date: 2026-07-18
- Decision owner: G004 alarm topology evidence gate
- Evidence record: [MORU-v1-Alarm-Device-Evidence.md](../qa/MORU-v1-Alarm-Device-Evidence.md)

## Decision

This ADR is G004's first story action and its sole evidence gate. MORU v1 ships the visible
notification-only downgrade. It does not select an AlarmKit routine-launch topology.

The shipped capability is a visible notification outcome only. A notification tap may use ordinary
app navigation, but it must not establish an AlarmKit DTO, occurrence, admission, or routine-start
state. No hidden path may convert a notification delivery or tap into routine execution.

The following are release-blocked until a later physical ADR amendment proves one exact topology:

- External AlarmKit routine launch.
- In-app alarm ring or snooze.
- AlarmKit lifecycle acknowledgement.
- Independent vibration parity.

## Evidence boundary

On 2026-07-18, the Xcode 26.5 / iOS SDK 26.5 registered physical devices were offline or
unavailable. Therefore, no foreground, background, locked, or killed trace can prove an exact
AlarmKit DTO receipt, app or extension open behavior, or routine admission.

Simulator behavior, source inspection, and inferred framework behavior are not physical proof and
must not be presented as such.

## Options evaluated

### Main-app intent/process mutex

Candidate: the main app receives the signal while a process mutex guards admission.

Selection needs physical proof of the exact delivered DTO, app process/open behavior, and admission
under the mutex. Decision: not selected; proof is absent.

### Extension/App Group sidecar

Candidate: an extension receives the DTO, writes an App Group sidecar, and the app consumes it.

Selection needs physical proof of DTO delivery, extension execution, sidecar handoff, app open
behavior, and admission. Decision: not selected; proof is absent.

### Visible notification-only downgrade

This option makes no claim of external AlarmKit ingress or routine admission and remains truthful
while devices are unavailable. Decision: selected.

## Fail-closed implementation map

- Product work may implement only the visible notification capability and its truthful permission
  and retry states.
- A missing, malformed, duplicate, or unproven AlarmKit signal must not create a routine launch,
  ring, snooze, lifecycle acknowledgement, vibration claim, or synthetic occurrence.
- Strict local storage and reset work may proceed only where it does not assume an unproven
  AlarmKit ingress, DTO, process, or admission topology.
- The conditional occurrence envelope, identity index, import, admission, lifecycle, receipt, and
  snooze runtime is not instantiated in this downgrade because no topology proved its ingress.
- Existing `PersistedAlarmPlatformState` rows describe only local-notification mutation truth;
  they are not AlarmKit occurrence, admission, ring, snooze, or lifecycle evidence.
- The main-app reset journal owns only generation, sealed notification cancellation inventory, and
  forward-only reset progress. It cannot accept or reconstruct an AlarmKit occurrence.
- Preserve Router Revision 5: trials save zero `RoutineRun` records; regular execution saves before
  exit. Preserve additive V2 identities and all existing trial and regular finalizer boundaries.
- Do not represent notification delivery, app opening, or a user-driven routine as AlarmKit
  admission evidence.

## Amendment criteria

A later ADR amendment may select exactly one topology only after physical iOS 26.5 evidence proves
all of the following for that topology in foreground, background, locked, and killed states:

1. The exact received AlarmKit DTO and its source.
2. The receiving target and observed process/open behavior.
3. The admission result for the intended routine, without fabricated lifecycle parity.

Until then, the notification-only downgrade remains the sole G004 release capability.
