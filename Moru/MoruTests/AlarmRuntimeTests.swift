//
//  AlarmRuntimeTests.swift
//  MoruTests
//
//  Created by Codex on 7/23/26.
//

import Foundation
import XCTest
@testable import Moru

final class AlarmRuntimeTests: XCTestCase {
  func testIngressStorePersistsOneEnvelopeAndConsumesItOnce() throws {
    let suiteName = "AlarmRuntimeTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let envelope = makeEnvelope(fireDate: Date(timeIntervalSince1970: 1_000))
    let latestEnvelope = makeEnvelope(
      fireDate: Date(timeIntervalSince1970: 2_000)
    )

    MoruAlarmRouteStore.savePendingEnvelope(envelope, defaults: defaults)
    MoruAlarmRouteStore.savePendingEnvelope(latestEnvelope, defaults: defaults)

    XCTAssertEqual(
      MoruAlarmRouteStore.pendingEnvelope(defaults: defaults),
      latestEnvelope
    )
    XCTAssertEqual(
      MoruAlarmRouteStore.consumePendingEnvelope(defaults: defaults),
      latestEnvelope
    )
    XCTAssertNil(MoruAlarmRouteStore.consumePendingEnvelope(defaults: defaults))

    defaults.set(
      Data("malformed".utf8),
      forKey: "moru.pendingAlarmIngressEnvelope"
    )
    XCTAssertNil(MoruAlarmRouteStore.consumePendingEnvelope(defaults: defaults))
    XCTAssertNil(
      defaults.object(forKey: "moru.pendingAlarmIngressEnvelope")
    )
  }

  func testIngressEnvelopeRoundTripsAsNotificationPayload() throws {
    let envelope = makeEnvelope(fireDate: Date(timeIntervalSince1970: 2_000))
    let value = try envelope.encodedString()
    let userInfo: [AnyHashable: Any] = [
      AlarmIngressEnvelope.notificationUserInfoKey: value,
    ]

    XCTAssertEqual(
      UserNotificationAlarmSchedulingAdapter.ingress(from: userInfo),
      envelope
    )
    XCTAssertNil(
      UserNotificationAlarmSchedulingAdapter.ingress(
        from: [AlarmIngressEnvelope.notificationUserInfoKey: "malformed"]
      )
    )
  }

  func testLegacyIngressDefaultsToAlarmRingLaunch() throws {
    struct LegacyEnvelope: Encodable {
      let alarmID: UUID
      let routineID: UUID
      let scheduleID: UUID
      let kind: AlarmIngressKind
      let fireDate: Date
      let nonce: UUID
    }

    let envelope = makeEnvelope(
      fireDate: Date(timeIntervalSince1970: 1_000)
    )
    let legacy = LegacyEnvelope(
      alarmID: envelope.alarmID,
      routineID: envelope.routineID,
      scheduleID: envelope.scheduleID,
      kind: envelope.kind,
      fireDate: envelope.fireDate,
      nonce: envelope.nonce
    )
    let data = try JSONEncoder().encode(legacy)

    let decoded = try JSONDecoder().decode(
      AlarmIngressEnvelope.self,
      from: data
    )

    XCTAssertEqual(
      decoded.launchTarget,
      AlarmIngressLaunchTarget.alarmRing
    )
  }

  func testAlarmKitRoutineIntentRequestsDirectScheduledLaunch() throws {
    let template = makeEnvelope(
      fireDate: Date(timeIntervalSince1970: 1_000)
    )
    let fireDate = Date(timeIntervalSince1970: 3_000)
    let nonce = UUID()

    let ingress = OpenMoruRoutineIntent.makeIngress(
      encodedIngress: try template.encodedString(),
      fireDate: fireDate,
      nonce: nonce
    )

    XCTAssertEqual(ingress?.alarmID, template.alarmID)
    XCTAssertEqual(ingress?.routineID, template.routineID)
    XCTAssertEqual(ingress?.scheduleID, template.scheduleID)
    XCTAssertEqual(ingress?.kind, template.kind)
    XCTAssertEqual(ingress?.fireDate, fireDate)
    XCTAssertEqual(ingress?.nonce, nonce)
    XCTAssertEqual(ingress?.launchTarget, .scheduledRoutine)
    XCTAssertEqual(
      try ingress.map { try AlarmIngressEnvelope.decode($0.encodedString()) },
      ingress
    )
  }

  func testFallbackNotificationTapRefreshesOccurrenceForSharedIngress() throws {
    let scheduledAt = Date(timeIntervalSince1970: 500)
    let tappedAt = Date(timeIntervalSince1970: 1_000)
    let nonce = UUID()
    let template = makeEnvelope(
      fireDate: scheduledAt,
      launchTarget: .scheduledRoutine
    )
    let userInfo: [AnyHashable: Any] = [
      AlarmIngressEnvelope.notificationUserInfoKey:
        try template.encodedString(),
    ]

    let ingress = AlarmNotificationDelegate.makeIngress(
      from: userInfo,
      fireDate: tappedAt,
      nonce: nonce
    )

    XCTAssertEqual(ingress?.alarmID, template.alarmID)
    XCTAssertEqual(ingress?.routineID, template.routineID)
    XCTAssertEqual(ingress?.scheduleID, template.scheduleID)
    XCTAssertEqual(ingress?.kind, template.kind)
    XCTAssertEqual(ingress?.fireDate, tappedAt)
    XCTAssertEqual(ingress?.nonce, nonce)
    XCTAssertEqual(ingress?.launchTarget, .alarmRing)
  }

  @MainActor
  func testDirectScheduledLaunchTransitionsOnlyAfterStopCompletes() {
    let routineID = UUID()
    let context = makeContext(
      routineID: routineID,
      launchTarget: .scheduledRoutine
    )
    let admission = AppNavigationReducer.admitPresentation(
      .startingScheduledRoutine(context: context),
      from: .idle
    )

    guard case .presented(let token) = admission.attempt else {
      XCTFail("The direct launch should reserve a noninteractive presentation.")
      return
    }
    guard case .startingScheduledRoutine(
      let startingContext,
      let startingToken
    ) = admission.state.visiblePresentation else {
      XCTFail("The routine must not open before the alarm stop completes.")
      return
    }
    XCTAssertEqual(startingContext, context)
    XCTAssertEqual(startingToken, token)

    let completion = AppNavigationReducer.reduce(
      state: admission.state,
      action: .completeScheduledRoutineStart(
        routineID: routineID,
        startingPresentationToken: token
      )
    )

    guard case .regularRoutine(
      let presentedRoutineID,
      let source,
      _
    ) = completion.state.visiblePresentation else {
      XCTFail("A successful stop should open the scheduled RoutinePlayer.")
      return
    }
    XCTAssertEqual(presentedRoutineID, routineID)
    XCTAssertEqual(source, .scheduled)
  }

  @MainActor
  func testDirectScheduledLaunchFailureBecomesRetryableAlarmRing() {
    let context = makeContext(
      routineID: UUID(),
      launchTarget: .scheduledRoutine
    )
    let admission = AppNavigationReducer.admitPresentation(
      .startingScheduledRoutine(context: context),
      from: .idle
    )

    guard case .presented(let token) = admission.attempt else {
      XCTFail("The direct launch should be admitted.")
      return
    }

    let failure = AppNavigationReducer.reduce(
      state: admission.state,
      action: .failScheduledRoutineStart(
        startingPresentationToken: token
      )
    )

    guard case .alarmRing(
      let retryContext,
      let retryToken
    ) = failure.state.visiblePresentation else {
      XCTFail("A failed stop should leave the manual AlarmRing retry path.")
      return
    }
    XCTAssertEqual(retryToken, token)
    XCTAssertEqual(retryContext.ingress.launchTarget, .alarmRing)
    XCTAssertEqual(retryContext.ingress.alarmID, context.ingress.alarmID)
  }

  @MainActor
  func testDirectScheduledLaunchRejectsStaleCompletionToken() {
    let context = makeContext(
      routineID: UUID(),
      launchTarget: .scheduledRoutine
    )
    let admission = AppNavigationReducer.admitPresentation(
      .startingScheduledRoutine(context: context),
      from: .idle
    )

    let staleCompletion = AppNavigationReducer.reduce(
      state: admission.state,
      action: .completeScheduledRoutineStart(
        routineID: context.ingress.routineID,
        startingPresentationToken: UUID()
      )
    )

    XCTAssertEqual(staleCompletion.state, admission.state)
  }

  @MainActor
  func testRecurringIngressResolvesExactRoutineAndStopsBeforeStarting() async throws {
    let fixture = makeFixture()
    let resolution = await fixture.runtime.resolve(fixture.envelope)

    guard case .route(let context) = resolution else {
      XCTFail("The valid recurring route should open AlarmRing.")
      return
    }

    XCTAssertEqual(context.ingress.routineID, fixture.routine.id)
    XCTAssertEqual(context.routineName, fixture.routine.name)
    XCTAssertEqual(context.routineMinutes, 3)

    try await fixture.runtime.startRoutine(from: context)

    XCTAssertEqual(fixture.primary.stopIDs, [fixture.scheduleID])
    XCTAssertTrue(fixture.stateRepository.snoozedAlarms.isEmpty)
  }

  @MainActor
  func testStaleInactiveAndMismatchedRoutesAreIgnored() async {
    let now = Date(timeIntervalSince1970: 10_000)
    let staleFixture = makeFixture(now: now)
    let staleEnvelope = makeEnvelope(
      routineID: staleFixture.routine.id,
      scheduleID: staleFixture.scheduleID,
      fireDate: now.addingTimeInterval(-31 * 60)
    )

    let staleResolution = await staleFixture.runtime.resolve(staleEnvelope)
    XCTAssertEqual(staleResolution, .ignored(.stale))

    var inactiveRoutine = staleFixture.routine
    inactiveRoutine.isActive = false
    staleFixture.routineRepository.routines = [inactiveRoutine]
    let inactiveResolution = await staleFixture.runtime.resolve(
      staleFixture.envelope
    )
    XCTAssertEqual(inactiveResolution, .ignored(.routineInactive))

    staleFixture.routineRepository.routines = [staleFixture.routine]
    let mismatchedEnvelope = makeEnvelope(
      routineID: staleFixture.routine.id,
      scheduleID: UUID(),
      fireDate: now
    )
    let mismatchResolution = await staleFixture.runtime.resolve(
      mismatchedEnvelope
    )
    XCTAssertEqual(mismatchResolution, .ignored(.scheduleMismatch))
  }

  @MainActor
  func testEverySnoozeOptionSchedulesExactFixedDateAndKeepsRecurringAlarm() async throws {
    let now = Date(timeIntervalSince1970: 20_000)

    for minutes in DefaultAlarmRuntimeCoordinator.snoozeOptions {
      let snoozeID = UUID()
      let fixture = makeFixture(now: now, makeID: { snoozeID })
      let context = try await resolvedContext(fixture)
      let record = try await fixture.runtime.snooze(
        context: context,
        minutes: minutes
      )

      XCTAssertEqual(record.id, snoozeID)
      XCTAssertEqual(
        record.fireDate,
        now.addingTimeInterval(TimeInterval(minutes * 60))
      )
      XCTAssertEqual(fixture.primary.snoozeRequests.last?.fireDate, record.fireDate)
      XCTAssertEqual(fixture.primary.stopIDs, [fixture.scheduleID])
      XCTAssertTrue(
        fixture.primary.cancellationBatches
          .allSatisfy { !$0.contains(fixture.scheduleID.uuidString.lowercased()) }
      )
      XCTAssertEqual(
        fixture.stateRepository.snoozedAlarms[record.id],
        record
      )
    }
  }

  @MainActor
  func testSnoozeFallsBackWhenAlarmKitIsUnavailable() async throws {
    let fixture = makeFixture(
      primaryAuthorization: .denied,
      fallbackAuthorization: .authorized
    )
    let context = try await resolvedContext(fixture)

    let record = try await fixture.runtime.snooze(context: context, minutes: 10)

    XCTAssertTrue(fixture.primary.snoozeRequests.isEmpty)
    XCTAssertEqual(fixture.fallback.snoozeRequests.count, 1)
    XCTAssertEqual(record.backend, .localNotification)
    XCTAssertEqual(fixture.primary.stopIDs, [fixture.scheduleID])
  }

  @MainActor
  func testStopFailureCancelsCompensatingSnoozeAndKeepsAlarmRingRetryable() async throws {
    let fixture = makeFixture()
    fixture.primary.stopError = AlarmRuntimeTestError.stop
    let context = try await resolvedContext(fixture)

    do {
      _ = try await fixture.runtime.snooze(context: context, minutes: 5)
      XCTFail("A current-alert stop failure should keep AlarmRing open.")
    } catch {
      XCTAssertEqual(error as? AlarmRuntimeError, .stopFailed)
    }

    let newIdentifier = try XCTUnwrap(
      fixture.primary.snoozeRequests.first?.alarmID.uuidString.lowercased()
    )
    XCTAssertTrue(
      fixture.primary.cancellationBatches.contains([newIdentifier])
    )
    XCTAssertTrue(fixture.stateRepository.snoozedAlarms.isEmpty)
  }

  @MainActor
  func testReplacingSnoozeStopsCurrentAlertAndMaintainsOneLogicalRecord() async throws {
    let now = Date(timeIntervalSince1970: 30_000)
    let currentSnoozeID = UUID()
    let nextSnoozeID = UUID()
    let fixture = makeFixture(now: now, makeID: { nextSnoozeID })
    let currentRecord = SnoozedAlarmRecord(
      id: currentSnoozeID,
      scheduleID: fixture.scheduleID,
      routineID: fixture.routine.id,
      fireDate: now,
      backend: .alarmKit,
      platformIdentifiers: [currentSnoozeID.uuidString.lowercased()],
      createdAt: now.addingTimeInterval(-300)
    )
    fixture.stateRepository.snoozedAlarms[currentSnoozeID] = currentRecord
    let envelope = makeEnvelope(
      alarmID: currentSnoozeID,
      routineID: fixture.routine.id,
      scheduleID: fixture.scheduleID,
      kind: .snooze,
      fireDate: now
    )
    let resolution = await fixture.runtime.resolve(envelope)
    guard case .route(let context) = resolution else {
      XCTFail("The persisted snooze should be routable.")
      return
    }

    let nextRecord = try await fixture.runtime.snooze(
      context: context,
      minutes: 15
    )

    XCTAssertEqual(fixture.primary.stopIDs, [currentSnoozeID])
    XCTAssertNil(fixture.stateRepository.snoozedAlarms[currentSnoozeID])
    XCTAssertEqual(
      fixture.stateRepository.snoozedAlarms[nextSnoozeID],
      nextRecord
    )
    XCTAssertEqual(fixture.stateRepository.snoozedAlarms.count, 1)
  }

  @MainActor
  func testReplacingSnoozeRestoresPreviousRegistryWhenStopFails() async throws {
    let now = Date(timeIntervalSince1970: 35_000)
    let currentSnoozeID = UUID()
    let nextSnoozeID = UUID()
    let fixture = makeFixture(now: now, makeID: { nextSnoozeID })
    let currentRecord = SnoozedAlarmRecord(
      id: currentSnoozeID,
      scheduleID: fixture.scheduleID,
      routineID: fixture.routine.id,
      fireDate: now,
      backend: .alarmKit,
      platformIdentifiers: [currentSnoozeID.uuidString.lowercased()],
      createdAt: now.addingTimeInterval(-300)
    )
    fixture.stateRepository.snoozedAlarms[currentSnoozeID] = currentRecord
    fixture.primary.stopError = AlarmRuntimeTestError.stop
    let envelope = makeEnvelope(
      alarmID: currentSnoozeID,
      routineID: fixture.routine.id,
      scheduleID: fixture.scheduleID,
      kind: .snooze,
      fireDate: now
    )
    let resolution = await fixture.runtime.resolve(envelope)
    guard case .route(let context) = resolution else {
      XCTFail("The persisted snooze should be routable.")
      return
    }

    do {
      _ = try await fixture.runtime.snooze(context: context, minutes: 30)
      XCTFail("The failed stop should compensate the replacement snooze.")
    } catch {
      XCTAssertEqual(error as? AlarmRuntimeError, .stopFailed)
    }

    XCTAssertEqual(
      fixture.stateRepository.snoozedAlarms,
      [currentSnoozeID: currentRecord]
    )
    XCTAssertTrue(
      fixture.primary.cancellationBatches.contains(
        [nextSnoozeID.uuidString.lowercased()]
      )
    )
  }

  @MainActor
  func testNavigationDefersOnlyLatestAlarmAndStartsScheduledPlayer() {
    let coordinator = AppNavigationCoordinator()
    let routineID = UUID()
    let firstContext = makeContext(routineID: routineID)
    let latestContext = makeContext(routineID: routineID)

    guard case .presented(let routineToken) = coordinator.presentRegularRoutine(
      routineID: UUID()
    ) else {
      XCTFail("The manual routine should be presented.")
      return
    }

    XCTAssertEqual(
      coordinator.presentAlarmRing(context: firstContext),
      .deferredBusy
    )
    XCTAssertEqual(
      coordinator.presentAlarmRing(context: latestContext),
      .deferredBusy
    )
    XCTAssertNil(coordinator.takeDeferredAlarmRingContext())

    XCTAssertEqual(
      coordinator.handle(
        event: .exitRequested(.userDismissed),
        presentationToken: routineToken
      ),
      .dismiss(token: routineToken)
    )
    coordinator.presentationBindingDidChange(to: nil)
    XCTAssertEqual(coordinator.presentationDidDismiss(), .none)
    XCTAssertEqual(coordinator.takeDeferredAlarmRingContext(), latestContext)

    guard case .presented(let alarmToken) = coordinator.presentAlarmRing(
      context: latestContext
    ) else {
      XCTFail("AlarmRing should be admitted after the busy flow ends.")
      return
    }

    XCTAssertTrue(
      coordinator.startScheduledRoutine(
        routineID: routineID,
        alarmPresentationToken: alarmToken
      )
    )

    guard case .regularRoutine(
      let presentedRoutineID,
      let source,
      _
    ) = coordinator.presentation else {
      XCTFail("Starting AlarmRing should replace it with RoutinePlayer.")
      return
    }
    XCTAssertEqual(presentedRoutineID, routineID)
    XCTAssertEqual(source, .scheduled)
  }

  @MainActor
  func testRoutineMutationCancelsRelatedSnoozeBeforeKeepingRecurringSchedule() async throws {
    let fixture = makeFixture()
    let snoozeID = UUID()
    fixture.primary.identifiers.insert(snoozeID.uuidString.lowercased())
    fixture.stateRepository.snoozedAlarms[snoozeID] = SnoozedAlarmRecord(
      id: snoozeID,
      scheduleID: fixture.scheduleID,
      routineID: fixture.routine.id,
      fireDate: Date().addingTimeInterval(300),
      backend: .alarmKit,
      platformIdentifiers: [snoozeID.uuidString.lowercased()],
      createdAt: Date()
    )
    let coordinator = DefaultAlarmScheduleMutationCoordinator(
      routineRepository: fixture.routineRepository,
      stateRepository: fixture.stateRepository,
      primaryScheduler: fixture.primary,
      fallbackScheduler: fixture.fallback
    )

    let result = try await coordinator.apply(
      .synchronize(routines: [fixture.routine])
    )

    XCTAssertFalse(result.requiresRepair)
    XCTAssertTrue(fixture.stateRepository.snoozedAlarms.isEmpty)
    XCTAssertTrue(
      fixture.primary.cancellationBatches.contains(
        [snoozeID.uuidString.lowercased()]
      )
    )
    XCTAssertTrue(fixture.primary.scheduleRequests.isEmpty)
  }

  @MainActor
  func testDeactivateDeleteAndResetCancelRelatedSnoozeState() async throws {
    let deactivateFixture = makeFixture()
    let deactivateSnooze = installSnooze(in: deactivateFixture)
    var inactiveRoutine = deactivateFixture.routine
    inactiveRoutine.isActive = false
    inactiveRoutine.alarmSchedule?.isEnabled = false
    let deactivateCoordinator = makeMutationCoordinator(deactivateFixture)

    _ = try await deactivateCoordinator.apply(
      .synchronize(routines: [inactiveRoutine])
    )

    XCTAssertNil(
      deactivateFixture.stateRepository.snoozedAlarms[deactivateSnooze.id]
    )
    XCTAssertNil(
      deactivateFixture.stateRepository.records[deactivateFixture.scheduleID]
    )

    let deleteFixture = makeFixture()
    let deleteSnooze = installSnooze(in: deleteFixture)
    let deleteCoordinator = makeMutationCoordinator(deleteFixture)

    _ = try await deleteCoordinator.apply(
      .delete(scheduleID: deleteFixture.scheduleID)
    )

    XCTAssertNil(deleteFixture.stateRepository.snoozedAlarms[deleteSnooze.id])
    XCTAssertTrue(deleteFixture.stateRepository.records.isEmpty)

    let resetFixture = makeFixture()
    let resetSnooze = installSnooze(in: resetFixture)
    let resetCoordinator = makeMutationCoordinator(resetFixture)

    try await resetCoordinator.cancelAllForReset()

    XCTAssertTrue(resetFixture.stateRepository.snoozedAlarms.isEmpty)
    XCTAssertTrue(resetFixture.stateRepository.records.isEmpty)
    XCTAssertTrue(
      resetFixture.primary.cancellationBatches.contains { batch in
        Set(batch).isSuperset(
          of: [
            resetFixture.scheduleID.uuidString.lowercased(),
            resetSnooze.id.uuidString.lowercased(),
          ]
        )
      }
    )
  }

  @MainActor
  func testResetWaitsForInFlightRuntimeSnoozeOnSharedMutationGate() async throws {
    let fixture = makeFixture()
    let gate = AlarmMutationGate()
    let runtime = DefaultAlarmRuntimeCoordinator(
      routineRepository: fixture.routineRepository,
      stateRepository: fixture.stateRepository,
      primaryScheduler: fixture.primary,
      fallbackScheduler: fixture.fallback,
      now: { fixture.envelope.fireDate },
      gate: gate
    )
    let resetCoordinator = DefaultAlarmScheduleMutationCoordinator(
      routineRepository: fixture.routineRepository,
      stateRepository: fixture.stateRepository,
      primaryScheduler: fixture.primary,
      fallbackScheduler: fixture.fallback,
      gate: gate
    )
    let resolution = await runtime.resolve(fixture.envelope)
    guard case .route(let context) = resolution else {
      XCTFail("The recurring alarm should be routable.")
      return
    }
    fixture.primary.shouldBlockSnoozeScheduling = true

    let snoozeTask = Task {
      try await runtime.snooze(context: context, minutes: 5)
    }
    await fixture.primary.waitUntilSnoozeSchedulingStarts()
    let resetTask = Task {
      try await resetCoordinator.cancelAllForReset()
    }
    await Task.yield()

    XCTAssertFalse(fixture.stateRepository.records.isEmpty)

    fixture.primary.finishSnoozeScheduling()
    _ = try await snoozeTask.value
    try await resetTask.value

    XCTAssertTrue(fixture.stateRepository.records.isEmpty)
    XCTAssertTrue(fixture.stateRepository.snoozedAlarms.isEmpty)
  }

  @MainActor
  private func resolvedContext(
    _ fixture: AlarmRuntimeFixture
  ) async throws -> AlarmRingContext {
    let resolution = await fixture.runtime.resolve(fixture.envelope)
    guard case .route(let context) = resolution else {
      throw AlarmRuntimeTestError.unexpectedResolution
    }
    return context
  }
}

@MainActor
private func installSnooze(
  in fixture: AlarmRuntimeFixture
) -> SnoozedAlarmRecord {
  let snoozeID = UUID()
  let identifier = snoozeID.uuidString.lowercased()
  let record = SnoozedAlarmRecord(
    id: snoozeID,
    scheduleID: fixture.scheduleID,
    routineID: fixture.routine.id,
    fireDate: Date().addingTimeInterval(300),
    backend: .alarmKit,
    platformIdentifiers: [identifier],
    createdAt: Date()
  )
  fixture.primary.identifiers.insert(identifier)
  fixture.stateRepository.snoozedAlarms[snoozeID] = record
  return record
}

@MainActor
private func makeMutationCoordinator(
  _ fixture: AlarmRuntimeFixture
) -> DefaultAlarmScheduleMutationCoordinator {
  DefaultAlarmScheduleMutationCoordinator(
    routineRepository: fixture.routineRepository,
    stateRepository: fixture.stateRepository,
    primaryScheduler: fixture.primary,
    fallbackScheduler: fixture.fallback
  )
}

@MainActor
private struct AlarmRuntimeFixture {
  let routine: Routine
  let scheduleID: UUID
  let envelope: AlarmIngressEnvelope
  let routineRepository: AlarmRuntimeRoutineRepository
  let stateRepository: AlarmRuntimeStateRepository
  let primary: AlarmRuntimeTestScheduler
  let fallback: AlarmRuntimeTestScheduler
  let runtime: DefaultAlarmRuntimeCoordinator
}

@MainActor
private func makeFixture(
  now: Date = Date(timeIntervalSince1970: 5_000),
  makeID: @escaping () -> UUID = UUID.init,
  primaryAuthorization: AlarmAuthorizationState = .authorized,
  fallbackAuthorization: AlarmAuthorizationState = .authorized
) -> AlarmRuntimeFixture {
  let routineID = UUID()
  let scheduleID = UUID()
  let routine = makeAlarmRuntimeRoutine(
    routineID: routineID,
    scheduleID: scheduleID
  )
  let routineRepository = AlarmRuntimeRoutineRepository(routines: [routine])
  let stateRepository = AlarmRuntimeStateRepository()
  let primary = AlarmRuntimeTestScheduler(
    backend: .alarmKit,
    authorization: primaryAuthorization
  )
  let fallback = AlarmRuntimeTestScheduler(
    backend: .localNotification,
    authorization: fallbackAuthorization
  )
  let request = AlarmScheduleRequest(routine: routine)!
  let identifier = scheduleID.uuidString.lowercased()
  primary.identifiers.insert(identifier)
  stateRepository.records[scheduleID] = AlarmDeliveryRecord(
    request: request,
    backend: .alarmKit,
    state: .scheduled,
    platformIdentifiers: [identifier],
    lastErrorMessage: nil,
    updatedAt: now
  )
  let envelope = makeEnvelope(
    routineID: routineID,
    scheduleID: scheduleID,
    fireDate: now
  )
  let runtime = DefaultAlarmRuntimeCoordinator(
    routineRepository: routineRepository,
    stateRepository: stateRepository,
    primaryScheduler: primary,
    fallbackScheduler: fallback,
    now: { now },
    makeID: makeID
  )
  return AlarmRuntimeFixture(
    routine: routine,
    scheduleID: scheduleID,
    envelope: envelope,
    routineRepository: routineRepository,
    stateRepository: stateRepository,
    primary: primary,
    fallback: fallback,
    runtime: runtime
  )
}

private func makeEnvelope(
  alarmID: UUID? = nil,
  routineID: UUID = UUID(),
  scheduleID: UUID = UUID(),
  kind: AlarmIngressKind = .recurring,
  fireDate: Date,
  launchTarget: AlarmIngressLaunchTarget = .alarmRing
) -> AlarmIngressEnvelope {
  AlarmIngressEnvelope(
    alarmID: alarmID ?? scheduleID,
    routineID: routineID,
    scheduleID: scheduleID,
    kind: kind,
    fireDate: fireDate,
    nonce: UUID(),
    launchTarget: launchTarget
  )
}

private func makeContext(
  routineID: UUID,
  launchTarget: AlarmIngressLaunchTarget = .alarmRing
) -> AlarmRingContext {
  AlarmRingContext(
    ingress: makeEnvelope(
      routineID: routineID,
      fireDate: Date(),
      launchTarget: launchTarget
    ),
    routineName: "활력 루틴",
    routineMinutes: 10
  )
}

@MainActor
private func makeAlarmRuntimeRoutine(
  routineID: UUID,
  scheduleID: UUID
) -> Routine {
  Routine(
    id: routineID,
    name: "활력 루틴",
    steps: [
      RoutineStep(
        type: .confirm,
        title: "물 마시기",
        order: 0,
        estimatedSeconds: 60
      ),
      RoutineStep(
        type: .timer,
        title: "스트레칭",
        order: 1,
        estimatedSeconds: 120
      ),
    ],
    alarmSchedule: AlarmSchedule(
      id: scheduleID,
      hour: 7,
      minute: 30,
      weekdays: [.monday, .wednesday, .friday]
    )
  )
}

private enum AlarmRuntimeTestError: Error {
  case stop
  case cancellation
  case scheduling
  case persistence
  case unexpectedResolution
}

@MainActor
private final class AlarmRuntimeTestScheduler: AlarmScheduling {
  let backend: AlarmDeliveryBackend
  var authorization: AlarmAuthorizationState
  var identifiers: Set<String> = []
  var stopError: Error?
  var cancellationError: Error?
  var schedulingError: Error?
  var shouldBlockSnoozeScheduling = false
  private(set) var scheduleRequests: [AlarmScheduleRequest] = []
  private(set) var snoozeRequests: [AlarmSnoozeRequest] = []
  private(set) var stopIDs: [UUID] = []
  private(set) var cancellationBatches: [[String]] = []
  private var didStartSnoozeScheduling = false
  private var snoozeSchedulingContinuation: CheckedContinuation<Void, Never>?

  init(
    backend: AlarmDeliveryBackend,
    authorization: AlarmAuthorizationState
  ) {
    self.backend = backend
    self.authorization = authorization
  }

  func authorizationState() async -> AlarmAuthorizationState {
    authorization
  }

  func requestAuthorization() async throws -> AlarmAuthorizationState {
    authorization
  }

  func scheduleRecurring(_ request: AlarmScheduleRequest) async throws -> [String] {
    scheduleRequests.append(request)
    if let schedulingError {
      throw schedulingError
    }
    let values = [request.scheduleID.uuidString.lowercased()]
    identifiers.formUnion(values)
    return values
  }

  func scheduleSnooze(_ request: AlarmSnoozeRequest) async throws -> [String] {
    snoozeRequests.append(request)
    if shouldBlockSnoozeScheduling {
      didStartSnoozeScheduling = true
      await withCheckedContinuation { continuation in
        snoozeSchedulingContinuation = continuation
      }
    }
    if let schedulingError {
      throw schedulingError
    }
    let values: [String]
    switch backend {
    case .alarmKit:
      values = [request.alarmID.uuidString.lowercased()]
    case .localNotification:
      values = [
        UserNotificationAlarmSchedulingAdapter.snoozeRequestIdentifier(
          alarmID: request.alarmID
        ),
      ]
    }
    identifiers.formUnion(values)
    return values
  }

  func stop(id: UUID) async throws {
    stopIDs.append(id)
    if let stopError {
      throw stopError
    }
  }

  func cancel(identifiers: [String]) async throws {
    cancellationBatches.append(identifiers)
    if let cancellationError {
      throw cancellationError
    }
    self.identifiers.subtract(identifiers)
  }

  func snapshot() async throws -> AlarmPlatformSnapshot {
    AlarmPlatformSnapshot(backend: backend, identifiers: identifiers)
  }

  func waitUntilSnoozeSchedulingStarts() async {
    for _ in 0..<100 where !didStartSnoozeScheduling {
      await Task.yield()
    }
  }

  func finishSnoozeScheduling() {
    snoozeSchedulingContinuation?.resume()
    snoozeSchedulingContinuation = nil
  }
}

@MainActor
private final class AlarmRuntimeStateRepository: AlarmPlatformStateRepository {
  var records: [UUID: AlarmDeliveryRecord] = [:]
  var snoozedAlarms: [UUID: SnoozedAlarmRecord] = [:]
  var saveError: Error?

  func fetchRecords() throws -> [AlarmDeliveryRecord] {
    Array(records.values)
  }

  func record(scheduleID: UUID) throws -> AlarmDeliveryRecord? {
    records[scheduleID]
  }

  func saveRecord(_ record: AlarmDeliveryRecord) throws {
    records[record.scheduleID] = record
  }

  func deleteRecord(scheduleID: UUID) throws {
    records[scheduleID] = nil
  }

  func deleteAllRecords() throws {
    records.removeAll()
  }

  func fetchSnoozedAlarms() throws -> [SnoozedAlarmRecord] {
    Array(snoozedAlarms.values)
  }

  func saveSnoozedAlarm(_ record: SnoozedAlarmRecord) throws {
    if let saveError {
      throw saveError
    }
    snoozedAlarms[record.id] = record
  }

  func replaceSnoozedAlarm(
    scheduleID: UUID,
    with record: SnoozedAlarmRecord
  ) throws {
    if let saveError {
      throw saveError
    }
    snoozedAlarms = snoozedAlarms.filter {
      $0.value.scheduleID != scheduleID
    }
    snoozedAlarms[record.id] = record
  }

  func deleteSnoozedAlarm(id: UUID) throws {
    snoozedAlarms[id] = nil
  }

  func deleteAllSnoozedAlarms() throws {
    snoozedAlarms.removeAll()
  }
}

@MainActor
private final class AlarmRuntimeRoutineRepository: RoutineRepository {
  var routines: [Routine]

  init(routines: [Routine]) {
    self.routines = routines
  }

  func fetchRoutines() throws -> [Routine] {
    routines
  }

  func fetchActiveRoutines() throws -> [Routine] {
    routines.filter(\.isActive)
  }

  func routine(id: UUID) throws -> Routine? {
    routines.first { $0.id == id }
  }

  func saveRoutine(_ routine: Routine) throws {
    try saveRoutines([routine])
  }

  func saveRoutines(_ routines: [Routine]) throws {
    for routine in routines {
      if let index = self.routines.firstIndex(where: { $0.id == routine.id }) {
        self.routines[index] = routine
      } else {
        self.routines.append(routine)
      }
    }
  }

  func updateRoutineActivation(id: UUID, isActive: Bool) throws {
    guard let index = routines.firstIndex(where: { $0.id == id }) else {
      return
    }
    routines[index].isActive = isActive
  }

  func deleteRoutine(id: UUID) throws {
    routines.removeAll { $0.id == id }
  }
}
