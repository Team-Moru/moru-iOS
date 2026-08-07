# Server Routine TTS MVP

## Product boundary

- The local `Routine` and `RoutineStep` records are the source of truth.
- The app uses UUIDs. Server IDs remain `Int64` and live only in a separate
  TTS link record.
- There is no backup, restore, import, or multi-device synchronization.
- A server routine group is created only because the current server has no
  dedicated TTS job API.
- Local save, edit, and delete must succeed even when every TTS operation
  fails.

## MVP flow

1. Save the confirmed routine to SwiftData.
2. If the user is signed in, store a `creating` TTS link.
3. Call `POST /routine-groups` exactly once.
4. Validate the response and map:
   - local routine UUID to server `routineGroupId`
   - local step UUID to server `routineId`
   - server `routineId` to its generated `stepId` values and `orderIndex`
5. Poll `GET /routine-tts/{routineGroupId}/tts`.
6. When every expected server step is `COMPLETED`, download each HTTPS audio
   URL without the Moru bearer token.
7. Cache the files locally and mark the link `ready`.
8. At runtime, play cached server `intro` files in `orderIndex` order.
9. Use bundled audio for `remind` and `done`. Missing or damaged audio never
   blocks routine execution.

The TTS-only server request intentionally omits local alarm days and time and
sends `weatherNotificationEnabled: false`. Local scheduling remains the only
active schedule.

## Retry and invalidation rules

- Never automatically retry `POST /routine-groups`; the API has no
  idempotency key and a retry can create a duplicate group.
- Retry only TTS `GET` polling, with a bounded attempt count and delay.
- A server `FAILED` status, unknown status, unexpected ID, insecure URL,
  timeout, or download failure marks the link `failed`.
- Editing TTS-relevant local content changes its fingerprint, cancels the old
  job, removes old cached files, and starts a new job.
- Deleting a local routine immediately removes its link and cache. Deleting
  the server group is best-effort.
- Results from an old account, old fingerprint, or cancelled task cannot be
  persisted.
- Logging out keeps the cache but the signed-out app cannot resolve it.
  Withdrawal removes that member's links and generated audio.
- The MVP does not register a background task or automatically scan pending
  links at launch. If the process is killed during generation, saving the same
  routine again resumes polling from its stored server IDs.

## Current Swagger contracts

- `GET /tts`
  - returns the selectable server voice list and each `ttsId`
- `PATCH /members/me/tts`
  - bearer authentication
  - changes the signed-in member's server voice using `ttsId`
  - this is separate from the app's bundled, on-device guidance voice
- `POST /routine-groups`
  - bearer authentication
  - required request fields: `title`, `weatherNotificationEnabled`,
    `routines`
  - each routine requires `title`, `type`, `durationSecond`
  - response exposes `routineGroupId`, `routineId`, generated `stepId`, and
    `orderIndex`
- `GET /routine-tts/{routineGroupId}/tts`
  - bearer authentication
  - each generated step exposes `ttsStatus`, optional `ttsIntro`, and optional
    `s3Url`
  - known states: `PENDING`, `COMPLETED`, `FAILED`
- `DELETE /routine-groups/{routineGroupId}`
  - bearer authentication
  - used only for best-effort cleanup

## Backend contracts still needed

The deployed Swagger does not promise the following behavior. These items
must be confirmed with a signed-in smoke test or added to the backend
contract.

1. Creating a routine group automatically starts TTS generation.
2. The create response preserves the request routine order. A future API
   should accept a client UUID or idempotency key so order is not an identity
   contract.
3. The returned S3 URL is downloadable without a Moru bearer token, has a
   documented expiry, and returns a supported audio format.
4. TTS-only groups can be distinguished from backup data and do not trigger
   server alarms or weather notifications.
5. New TTS generation uses the member's currently selected server `ttsId`,
   and the server documents when that voice selection is captured.
6. Changing the member's server voice either regenerates existing audio or
   provides a documented revision/invalidation mechanism for cached audio.
7. Deleting or withdrawing an account removes TTS objects and cached server
   files according to a documented retention policy.

Until the server has a dedicated TTS job endpoint, TTS-only groups can appear
in the server routine-group list. This is the main known compromise of the
MVP. The server `intro` voice can also differ from the bundled `remind` and
`done` voice until the server exposes matching cue types.

## Signed-in smoke test

Use a disposable routine and account-visible cleanup:

1. Select a server voice.
2. Save one routine with one uniquely named local step.
3. Confirm `POST /routine-groups` returns positive group, routine, and nested
   step IDs.
4. Confirm TTS polling moves from `PENDING` to `COMPLETED` without another
   generation request.
5. Download the URL without an Authorization header.
6. Confirm `AVAudioPlayer.prepareToPlay()` accepts every file.
7. Run the local routine and confirm the selected server voice plays first.
8. Delete the local routine and confirm the server cleanup request succeeds.
