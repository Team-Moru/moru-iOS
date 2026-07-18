# MORU v1 Alarm Device Evidence

- Evidence date: 2026-07-18
- Toolchain: Xcode 26.5 / iOS SDK 26.5
- Scope: Physical-device evidence for the G004 AlarmKit topology decision
- Related ADR: [MORU-v1-AlarmTopology-ADR.md](../architecture/MORU-v1-AlarmTopology-ADR.md)

## Recorded commands and observations

This record preserves the observed states. It does not reconstruct or claim raw command output that
was not retained.

```sh
xcrun xctrace list devices
```

Observed under `Devices Offline`:

- `민혁의 iPhone (26.5) (00008110-001C745C36D9801E)`
- `민혁의 iPad Pro (26.5) (00008027-000270840184402E)`

```sh
xcrun devicectl list devices
```

Observed state: both registered devices were unavailable.

## Missing required physical trace

No foreground, background, locked, or killed trace can be proven while both devices are offline or
unavailable. The following required evidence was not captured; no missing cell is a failure result.

| Device state | Exact AlarmKit DTO receipt | Target/process open behavior | Routine admission |
|---|---|---|---|
| Foreground | Not captured | Not captured | Not captured |
| Background | Not captured | Not captured | Not captured |
| Locked | Not captured | Not captured | Not captured |
| Killed | Not captured | Not captured | Not captured |

The missing matrix means no exact external DTO, receiver, opening behavior, or admission path is
physically proven. Simulators and source inspection are not substitutes for this physical trace.

## Decision

The G004 evidence gate selects the visible notification-only downgrade. It is the sole shipped
capability for this alarm surface until a later physical ADR amendment proves one exact topology.

External AlarmKit routine launch, in-app alarm ring or snooze, AlarmKit lifecycle acknowledgement,
and independent vibration parity are release-blocked. Notification delivery or a notification tap
must not be recorded or presented as an AlarmKit occurrence, admission, or lifecycle acknowledgement.

## Re-open checklist

Before amending the ADR:

1. Bring at least one registered iOS 26.5 physical device online and record its stable identifier,
   Xcode version, iOS version, and capture time.
2. Trigger the intended external AlarmKit path and preserve the directly observed exact DTO receipt,
   including the receiving target.
3. Capture foreground, background, locked, and killed traces with the observed process/open behavior
   and routine admission result for the same proposed topology.
4. Record failures, retries, duplicates, and any unavailable state without inventing a lifecycle,
   ring, snooze, or vibration result.
5. Amend the topology ADR only when one candidate has the complete physical DTO/open/admission proof;
   otherwise retain the notification-only downgrade.
