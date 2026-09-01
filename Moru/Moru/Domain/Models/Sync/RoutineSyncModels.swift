//
//  RoutineSyncModels.swift
//  Moru
//

import Foundation

nonisolated enum RoutineSyncServerNamespace: String, CaseIterable, Sendable {
  case production
  case staging
}

/// Local SwiftData remains the source of truth. These values only identify the
/// account-scoped server counterpart of a local entity.
nonisolated enum RoutineSyncEntityKind: String, CaseIterable, Sendable {
  /// Account-scoped commands such as the single active routine selection do
  /// not represent a remotely bindable entity.
  case account
  case routineGroup
  case routine
  case routineExecution
}

nonisolated struct RoutineServerBinding: Equatable, Sendable {
  let id: UUID
  let serverNamespace: RoutineSyncServerNamespace
  let memberID: Int64
  let entityKind: RoutineSyncEntityKind
  let localEntityID: UUID
  let remoteID: Int64
  let remoteRevision: String?
  let parentEntityKind: RoutineSyncEntityKind?
  let parentLocalEntityID: UUID?
  let createdAt: Date
  let updatedAt: Date

  /// Existing local UUID is the stable client entity identifier. The current
  /// server API does not accept it yet.
  var clientEntityID: UUID { localEntityID }
}

/// One validated local/server identity pair returned by a server response.
/// A routine-group response should record its group and child routine pairs
/// together so a partial mapping cannot escape.
nonisolated struct RoutineServerBindingAssignment: Equatable, Sendable {
  let entityKind: RoutineSyncEntityKind
  let localEntityID: UUID
  let remoteID: Int64
  let remoteRevision: String?
  /// Routine bindings belong to a group and execution bindings belong to a
  /// routine. This is local cleanup metadata, never a guessed server ID.
  let parentEntityKind: RoutineSyncEntityKind?
  let parentLocalEntityID: UUID?

  init(
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID,
    remoteID: Int64,
    remoteRevision: String? = nil,
    parentEntityKind: RoutineSyncEntityKind? = nil,
    parentLocalEntityID: UUID? = nil
  ) {
    self.entityKind = entityKind
    self.localEntityID = localEntityID
    self.remoteID = remoteID
    self.remoteRevision = remoteRevision
    self.parentEntityKind = parentEntityKind
    self.parentLocalEntityID = parentLocalEntityID
  }
}

/// Existing Swagger mutations that can eventually be driven from the local
/// outbox. Interactive AI judgment is excluded because its response is needed
/// immediately and the current endpoint has no replay contract.
nonisolated enum RoutineSyncOperation: String, CaseIterable, Sendable {
  case createRoutineGroup
  case addRoutine
  case setRoutineGroupActive
  case deleteRoutineGroup
  case deleteRoutine
  case saveRoutineExecution
  /// Account-level set-to-true request, dependent on a server-bound group.
  case completeOnboarding

  var deliveryPolicy: RoutineSyncDeliveryPolicy {
    switch self {
    case .setRoutineGroupActive:
      .requiresActiveSelectionContract
    case .deleteRoutineGroup, .deleteRoutine:
      .requiresAbsentIsSuccessContract
    case .createRoutineGroup, .addRoutine, .saveRoutineExecution:
      .requiresIdempotencyOrReconciliation
    case .completeOnboarding:
      .requiresOnboardingCompletionContract
    }
  }

  func accepts(_ entityKind: RoutineSyncEntityKind) -> Bool {
    switch self {
    case .createRoutineGroup, .deleteRoutineGroup:
      entityKind == .routineGroup
    case .setRoutineGroupActive, .completeOnboarding:
      // Legacy raw rows used routineGroup. New typed commands use account so
      // each signed-in account coalesces to exactly one desired selection.
      entityKind == .account || entityKind == .routineGroup
    case .addRoutine, .deleteRoutine:
      entityKind == .routine
    case .saveRoutineExecution:
      entityKind == .routineExecution
    }
  }
}

nonisolated enum RoutineSyncDeliveryPolicy: String, Sendable {
  /// The client and server both define at most one active group per account.
  case requiresActiveSelectionContract
  /// DELETE becomes replay-safe only after 404/verified absence counts as success.
  case requiresAbsentIsSuccessContract
  /// POST cannot be replayed safely without server support or reconciliation.
  case requiresIdempotencyOrReconciliation
  /// `POST /onboarding/complete` is a replay-safe server-side set-to-true.
  case requiresOnboardingCompletionContract
}

/// Server features that must be verified together before any routine Outbox
/// row can become deliverable. Declaring a header in Swagger is insufficient:
/// production admission also requires the matching E2E contract suite.
nonisolated struct RoutineSyncServerCapabilities: OptionSet, Equatable, Sendable {
  let rawValue: UInt16

  init(rawValue: UInt16) {
    self.rawValue = rawValue
  }

  static let idempotencyKey = Self(rawValue: 1 << 0)
  static let reconciliationLookup = Self(rawValue: 1 << 1)
  static let requiredResponseIDs = Self(rawValue: 1 << 2)
  static let clientEntityID = Self(rawValue: 1 << 3)
  static let clientExecutionID = Self(rawValue: 1 << 4)
  static let executionUpsert = Self(rawValue: 1 << 5)
  static let replaySafeDelete = Self(rawValue: 1 << 6)
  static let atomicSingleActive = Self(rawValue: 1 << 7)
  static let onboardingCompletion = Self(rawValue: 1 << 8)

  static let allRequired: Self = [
    .idempotencyKey,
    .reconciliationLookup,
    .requiredResponseIDs,
    .clientEntityID,
    .clientExecutionID,
    .executionUpsert,
    .replaySafeDelete,
    .atomicSingleActive,
    .onboardingCompletion,
  ]

  /// Capabilities verified on the production deployment used by P0 routine
  /// writes. Lookup/upsert are deliberately still absent. `atomicSingleActive`
  /// covers the `selectActiveRoutineGroup` (activate-one, server
  /// auto-deactivates the rest) path; the deactivate-with-no-replacement path
  /// is a separate `deactivateRoutineGroup` command against the same
  /// `PATCH .../active` contract.
  static let productionP0: Self = [
    .idempotencyKey,
    .requiredResponseIDs,
    .clientEntityID,
    .replaySafeDelete,
    .onboardingCompletion,
    .atomicSingleActive,
  ]
}

nonisolated struct RoutineSyncServerContract: Equatable, Sendable {
  let serverNamespace: RoutineSyncServerNamespace
  let capabilities: RoutineSyncServerCapabilities
  let isE2EVerified: Bool

  init(
    serverNamespace: RoutineSyncServerNamespace = .production,
    capabilities: RoutineSyncServerCapabilities,
    isE2EVerified: Bool
  ) {
    self.serverNamespace = serverNamespace
    self.capabilities = capabilities
    self.isE2EVerified = isE2EVerified
  }

  static let unavailable = Self(capabilities: [], isE2EVerified: false)

  static let productionP0 = Self(
    capabilities: .productionP0,
    isE2EVerified: true
  )

  func supports(_ operation: RoutineSyncOperation) -> Bool {
    guard isE2EVerified else { return false }
    let required: RoutineSyncServerCapabilities
    switch operation {
    case .createRoutineGroup, .addRoutine:
      required = [.idempotencyKey, .requiredResponseIDs, .clientEntityID]
    case .deleteRoutineGroup, .deleteRoutine:
      required = [.idempotencyKey, .requiredResponseIDs, .replaySafeDelete]
    case .saveRoutineExecution:
      required = [.idempotencyKey, .requiredResponseIDs]
    case .setRoutineGroupActive:
      required = [.idempotencyKey, .atomicSingleActive]
    case .completeOnboarding:
      required = [.onboardingCompletion]
    }
    return capabilities.intersection(required) == required
  }
}

nonisolated enum RoutineSyncMutationState: String, CaseIterable, Sendable {
  /// A future dispatch admission policy may move a safe operation here.
  case queued
  /// A sender has durably claimed one exact generation. The corresponding
  /// attempted payload remains persisted until a matching result is resolved.
  case attempting
  /// Current server API does not accept a client mutation ID or idempotency key.
  /// No automatic sender may process entries in this state.
  case waitingForServerContract
  /// A request may have reached the server, but the client cannot prove whether
  /// it committed. Manual or server-backed reconciliation is required.
  case needsReconciliation
  /// The exact attempted request is outside the server's completed-result
  /// retention window or hit an unclassifiable/key-reuse conflict. It must
  /// never be sent automatically with a new key.
  case blocked
}

/// Typed, versioned intent stored by the local outbox. It deliberately holds
/// local UUIDs instead of pretending the current server can understand them.
/// The sender remains disabled until the server contract is deployed.
nonisolated enum RoutineSyncCommand: Codable, Equatable, Sendable {
  case createRoutineGroup(RoutineSyncGroupSnapshot)
  case addRoutine(groupLocalID: UUID, routine: RoutineSyncRoutineSnapshot)
  case selectActiveRoutineGroup(selectedGroupLocalID: UUID?)
  /// The account's last locally-active group was turned off with no
  /// replacement selected, so there is nothing for `selectActiveRoutineGroup`
  /// to activate. Carries the specific local group whose server binding must
  /// be PATCHed to `isActive: false`, which a bare `nil` selection cannot
  /// express. Coalesces onto the same one-row-per-account outbox slot as
  /// `selectActiveRoutineGroup` (same operation/entityKind/localEntityID), so
  /// only the latest active/inactive intent for the account is ever pending.
  case deactivateRoutineGroup(groupLocalID: UUID)
  case deleteRoutineGroup(groupLocalID: UUID)
  case deleteRoutine(groupLocalID: UUID?, routineLocalID: UUID)
  case saveRoutineExecution(RoutineSyncExecutionSnapshot)
  /// Persists a local group ID. Its remote ID is resolved only immediately
  /// before the first wire request, after create-group settlement.
  case completeOnboarding(groupLocalID: UUID)

  var operation: RoutineSyncOperation {
    switch self {
    case .createRoutineGroup: .createRoutineGroup
    case .addRoutine: .addRoutine
    case .selectActiveRoutineGroup, .deactivateRoutineGroup: .setRoutineGroupActive
    case .deleteRoutineGroup: .deleteRoutineGroup
    case .deleteRoutine: .deleteRoutine
    case .saveRoutineExecution: .saveRoutineExecution
    case .completeOnboarding: .completeOnboarding
    }
  }

  var entityKind: RoutineSyncEntityKind {
    switch self {
    case .createRoutineGroup, .deleteRoutineGroup: .routineGroup
    case .addRoutine, .deleteRoutine: .routine
    case .selectActiveRoutineGroup, .deactivateRoutineGroup: .account
    case .saveRoutineExecution: .routineExecution
    case .completeOnboarding: .account
    }
  }

  /// The active selection has one row per account, even when selection is nil.
  var localEntityID: UUID {
    switch self {
    case .createRoutineGroup(let group): group.localID
    case .addRoutine(_, let routine): routine.localID
    case .selectActiveRoutineGroup, .deactivateRoutineGroup:
      RoutineSyncCommand.accountSelectionID
    case .deleteRoutineGroup(let groupLocalID): groupLocalID
    case .deleteRoutine(_, let routineLocalID): routineLocalID
    case .saveRoutineExecution(let execution): execution.localID
    case .completeOnboarding: RoutineSyncCommand.accountOnboardingCompletionID
    }
  }

  static let accountSelectionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  static let accountOnboardingCompletionID = UUID(
    uuidString: "00000000-0000-0000-0000-000000000002"
  )!
}

nonisolated struct RoutineSyncGroupSnapshot: Codable, Equatable, Sendable {
  let localID: UUID
  let name: String
  let summary: String
  let isActive: Bool
  let alarm: RoutineSyncAlarmSnapshot?
  let routines: [RoutineSyncRoutineSnapshot]

  init(
    localID: UUID,
    name: String,
    summary: String,
    isActive: Bool,
    alarm: RoutineSyncAlarmSnapshot?,
    routines: [RoutineSyncRoutineSnapshot]
  ) {
    self.localID = localID
    self.name = name
    self.summary = summary
    self.isActive = isActive
    self.alarm = alarm
    self.routines = routines
  }
}

nonisolated struct RoutineSyncRoutineSnapshot: Codable, Equatable, Sendable {
  let localID: UUID
  let title: String
  let type: String
  let durationSeconds: Int?
  let order: Int

  init(
    localID: UUID,
    title: String,
    type: String,
    durationSeconds: Int?,
    order: Int
  ) {
    self.localID = localID
    self.title = title
    self.type = type
    self.durationSeconds = durationSeconds
    self.order = order
  }
}

nonisolated struct RoutineSyncAlarmSnapshot: Codable, Equatable, Sendable {
  let hour: Int
  let minute: Int
  let weekdays: [Int]
  let isEnabled: Bool
  let includeWeather: Bool

  init(
    hour: Int,
    minute: Int,
    weekdays: [Int],
    isEnabled: Bool,
    includeWeather: Bool
  ) {
    self.hour = hour
    self.minute = minute
    self.weekdays = weekdays
    self.isEnabled = isEnabled
    self.includeWeather = includeWeather
  }
}

nonisolated struct RoutineSyncExecutionSnapshot: Codable, Equatable, Sendable {
  let runLocalID: UUID
  /// RoutineRun.routineID identifies the local group counterpart.
  let groupLocalID: UUID
  /// RoutineStepResult.stepID identifies the local child Routine counterpart.
  let routineLocalID: UUID
  let runStartedAt: Date
  let runCompletedAt: Date?
  let timeZoneIdentifier: String
  /// One outbox command is keyed by one stable RoutineStepResult UUID. The
  /// surrounding run is context only; it never determines coalescing.
  let result: RoutineSyncExecutionResultSnapshot

  var localID: UUID { result.localID }

  init(
    runLocalID: UUID,
    groupLocalID: UUID,
    routineLocalID: UUID,
    runStartedAt: Date,
    runCompletedAt: Date?,
    timeZoneIdentifier: String,
    result: RoutineSyncExecutionResultSnapshot
  ) {
    self.runLocalID = runLocalID
    self.groupLocalID = groupLocalID
    self.routineLocalID = routineLocalID
    self.runStartedAt = runStartedAt
    self.runCompletedAt = runCompletedAt
    self.timeZoneIdentifier = timeZoneIdentifier
    self.result = result
  }
}

nonisolated struct RoutineSyncExecutionResultSnapshot: Codable, Equatable, Sendable {
  let localID: UUID
  let completedAt: Date?
  let skipped: Bool
  let durationSeconds: Int?
  let inputText: String?
  let transcript: String?

  init(
    localID: UUID,
    completedAt: Date?,
    skipped: Bool,
    durationSeconds: Int?,
    inputText: String?,
    transcript: String?
  ) {
    self.localID = localID
    self.completedAt = completedAt
    self.skipped = skipped
    self.durationSeconds = durationSeconds
    self.inputText = inputText
    self.transcript = transcript
  }
}

nonisolated struct RoutineSyncAttempt: Equatable, Sendable {
  let generationID: UUID
  let generation: Int
  let payloadVersion: Int
  let payload: Data
  let wireRequest: RoutineSyncWireRequest?
  let attemptedAt: Date
}

nonisolated enum RoutineSyncHTTPMethod: String, Codable, Equatable, Sendable {
  case post = "POST"
  case delete = "DELETE"
  case patch = "PATCH"
}

/// Exact HTTP mutation artifact. Authentication is intentionally excluded;
/// path, method, and body are persisted before the first network write and
/// reused byte-for-byte for every replay.
nonisolated struct RoutineSyncWireRequest: Codable, Equatable, Sendable {
  let method: RoutineSyncHTTPMethod
  let path: String
  let body: Data

  init(method: RoutineSyncHTTPMethod, path: String, body: Data) {
    self.method = method
    self.path = path
    self.body = body
  }
}

nonisolated enum RoutineSyncBlockReason: String, Codable, Equatable, Sendable {
  case resultTTLExpired
  case processingRetryExhausted
  case idempotencyPayloadConflict
  case unknownConflict
  case definitiveServerRejection
  case invalidStoredRequest
}

nonisolated extension RoutineSyncAttempt {
  static let automaticReplayLifetime: TimeInterval = 24 * 60 * 60

  func isWithinAutomaticReplayWindow(at date: Date) -> Bool {
    date.timeIntervalSince(attemptedAt) >= 0
      && date.timeIntervalSince(attemptedAt) < Self.automaticReplayLifetime
  }
}

nonisolated enum PendingAccountCleanupPhase: String, Sendable {
  /// Written before the remote request. It proves only local intent, so it
  /// must never be treated as proof that the account was deleted remotely.
  case prepared
  /// Durably written immediately before the remote request. It deliberately
  /// remains ambiguous after transport/timeout/crash and cannot trigger
  /// automatic data or credential deletion.
  case attempting
  /// The withdrawal response was received. Local sync rows may now be removed,
  /// but this marker remains through `localDataCleaned` until matching
  /// credentials are durably removed.
  case remoteConfirmed
  /// All account-scoped sync rows are gone, but the marker stays until the
  /// matching Keychain session is removed. This closes the crash window
  /// between local cleanup and credential removal.
  case localDataCleaned
  /// A definitive pre-commit rejection can be cleaned up without touching
  /// account data. Keeping this explicit makes recovery auditable.
  case cancelled
}

nonisolated struct PendingAccountCleanupRecovery: Equatable, Sendable {
  let completedMemberIDs: [Int64]
  /// Only these exact accounts are ambiguous. A marker for old account A must
  /// never block a newer stored session for account B.
  let ambiguousMemberIDs: [Int64]

  var blocksSessionRestoration: Bool { !ambiguousMemberIDs.isEmpty }

  static let none = PendingAccountCleanupRecovery(
    completedMemberIDs: [],
    ambiguousMemberIDs: []
  )
}

nonisolated struct RoutineSyncMutation: Equatable, Sendable {
  let id: UUID
  let serverNamespace: RoutineSyncServerNamespace
  let memberID: Int64
  let operation: RoutineSyncOperation
  let entityKind: RoutineSyncEntityKind
  let localEntityID: UUID
  /// Stable for one exact payload generation. Rotates when payload changes.
  let generationID: UUID
  let generation: Int
  let payloadVersion: Int
  let payload: Data
  let state: RoutineSyncMutationState
  let attempt: RoutineSyncAttempt?
  let nextAttemptAt: Date?
  let processingConflictCount: Int
  let blockReason: RoutineSyncBlockReason?
  let createdAt: Date
  let updatedAt: Date
}

nonisolated struct EnqueuedRoutineSyncMutation: Equatable, Sendable {
  let memberID: Int64
  let operation: RoutineSyncOperation
  let entityKind: RoutineSyncEntityKind
  let localEntityID: UUID
  let payloadVersion: Int
  let payload: Data

  /// Compatibility-only initializer for pre-typed test rows. Production code
  /// must enqueue a RoutineSyncCommand below.

  init(
    memberID: Int64,
    operation: RoutineSyncOperation,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID,
    payloadVersion: Int = 1,
    payload: Data
  ) {
    self.memberID = memberID
    self.operation = operation
    self.entityKind = entityKind
    self.localEntityID = localEntityID
    self.payloadVersion = payloadVersion
    self.payload = payload
  }

  init(
    memberID: Int64,
    command: RoutineSyncCommand,
    payloadVersion: Int = 1
  ) throws {
    self.memberID = memberID
    operation = command.operation
    entityKind = command.entityKind
    localEntityID = command.localEntityID
    self.payloadVersion = payloadVersion
    payload = try JSONEncoder().encode(command)
  }
}

nonisolated enum RoutineSyncRepositoryError: Error, Equatable, Sendable {
  case invalidMemberID
  case invalidRemoteID
  case invalidPayload
  case remoteIDConflict(existing: Int64, incoming: Int64)
  case remoteIDAlreadyBound(remoteID: Int64, localEntityID: UUID)
  case duplicateBindingAssignment(
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID
  )
  case invalidOperationEntityCombination
  case reconciliationRequired(existingMutationID: UUID)
  case incompleteChildMapping
  case invalidParentBinding
  case missingPendingAccountCleanup
  case corruptedStoredValue(field: String)
}

extension RoutineSyncRoutineSnapshot {
  init(step: RoutineStep) {
    self.init(
      localID: step.id,
      title: step.title,
      type: step.type.rawValue,
      durationSeconds: step.estimatedSeconds,
      order: step.order
    )
  }
}

extension RoutineSyncGroupSnapshot {
  init(routine: Routine) {
    self.init(
      localID: routine.id,
      name: routine.name,
      summary: routine.summary,
      isActive: routine.isActive,
      alarm: routine.alarmSchedule.map {
        RoutineSyncAlarmSnapshot(
          hour: $0.hour,
          minute: $0.minute,
          weekdays: $0.weekdays.map(\.rawValue),
          isEnabled: $0.isEnabled,
          includeWeather: $0.includeWeather
        )
      },
      routines: routine.steps
        .sorted { $0.order < $1.order }
        .map(RoutineSyncRoutineSnapshot.init(step:))
    )
  }
}

extension RoutineSyncExecutionSnapshot {
  init(run: RoutineRun, result: RoutineStepResult, timeZone: TimeZone = .current) {
    self.init(
      runLocalID: run.id,
      groupLocalID: run.routineID,
      routineLocalID: result.stepID,
      runStartedAt: run.startedAt,
      runCompletedAt: run.completedAt,
      timeZoneIdentifier: timeZone.identifier,
      result: RoutineSyncExecutionResultSnapshot(
        localID: result.id,
        completedAt: result.completedAt,
        skipped: result.skipped,
        durationSeconds: result.durationSeconds,
        inputText: result.inputText,
        transcript: result.transcript
      )
    )
  }
}
