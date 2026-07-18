//
//  NotificationAlarmCoreTests.swift
//  MoruTests
//

import Foundation
import UserNotifications
import XCTest
@testable import Moru

@MainActor
final class NotificationAlarmCoreTests: XCTestCase {
  func testSchedulerCreatesDeterministicRequestsWithPassivePayload() async throws {
    let notificationCenter = NotificationCenterSpy()
    let scheduler = UserNotificationAlarmScheduler(notificationCenter: notificationCenter)
    let routineID = uuid("00000000-0000-0000-0000-000000000001")
    let scheduleID = uuid("00000000-0000-0000-0000-000000000002")
    let request = makeRequest(
      routineID: routineID,
      scheduleID: scheduleID,
      weekdays: [.friday, .monday]
    )

    try await scheduler.replace(request)

    let mondayID = UserNotificationAlarmScheduler.requestIdentifier(
      scheduleID: scheduleID,
      weekday: .monday
    )
    let fridayID = UserNotificationAlarmScheduler.requestIdentifier(
      scheduleID: scheduleID,
      weekday: .friday
    )
    XCTAssertEqual(Set(notificationCenter.pending.keys), Set([mondayID, fridayID]))

    let mondayRequest = try XCTUnwrap(notificationCenter.pending[mondayID])
    let trigger = try XCTUnwrap(mondayRequest.trigger as? UNCalendarNotificationTrigger)
    XCTAssertTrue(trigger.repeats)
    XCTAssertEqual(trigger.dateComponents.weekday, Weekday.monday.rawValue)
    XCTAssertEqual(trigger.dateComponents.hour, request.hour)
    XCTAssertEqual(trigger.dateComponents.minute, request.minute)
    XCTAssertEqual(mondayRequest.content.title, "MORU")
    XCTAssertEqual(mondayRequest.content.body, "아침 루틴 시작 시간이에요.")
    XCTAssertNotNil(mondayRequest.content.sound)
    XCTAssertEqual(mondayRequest.content.categoryIdentifier, "")
    XCTAssertEqual(mondayRequest.content.userInfo.count, 3)
    XCTAssertEqual(mondayRequest.content.userInfo["schemaVersion"] as? Int, 1)
    XCTAssertEqual(
      mondayRequest.content.userInfo["routineID"] as? String,
      routineID.uuidString.lowercased()
    )
    XCTAssertEqual(
      mondayRequest.content.userInfo["scheduleID"] as? String,
      scheduleID.uuidString.lowercased()
    )
  }
  func testSystemNotificationCenterPersistsAndCancelsDowngradeRequests() async throws {
    let center = UNUserNotificationCenter.current()
    let authorizationStatus = await center.notificationSettings().authorizationStatus
    switch authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      break
    case .notDetermined, .denied:
      throw XCTSkip("System notification persistence requires a preauthorized simulator.")
    @unknown default:
      throw XCTSkip("The simulator returned an unsupported notification authorization state.")
    }
    let scheduler = UserNotificationAlarmScheduler(center: center)
    let scheduleID = uuid("00000000-0000-0000-0000-000000000003")
    let request = makeRequest(scheduleID: scheduleID, weekdays: [.monday, .friday])
    let expectedIDs = Set(
      request.normalizedWeekdays.map {
        UserNotificationAlarmScheduler.requestIdentifier(
          scheduleID: scheduleID,
          weekday: $0
        )
      }
    )
    defer {
      center.removePendingNotificationRequests(withIdentifiers: Array(expectedIDs))
      center.removeDeliveredNotifications(withIdentifiers: Array(expectedIDs))
    }

    try await scheduler.replace(request)

    let scheduledIDs = Set(
      await center.pendingNotificationRequests()
        .map(\.identifier)
        .filter(expectedIDs.contains)
    )
    XCTAssertEqual(scheduledIDs, expectedIDs)

    try await scheduler.cancel(scheduleID: scheduleID)
    let remainingIDs = Set(
      await center.pendingNotificationRequests()
        .map(\.identifier)
        .filter(expectedIDs.contains)
    )
    XCTAssertTrue(remainingIDs.isEmpty)
  }

  func testRepeatingRequestUsesWallClockComponentsForDSTTransitions() async throws {
    let notificationCenter = NotificationCenterSpy()
    let scheduler = UserNotificationAlarmScheduler(notificationCenter: notificationCenter)
    let request = makeRequest(weekdays: [.sunday])

    try await scheduler.replace(request)

    let scheduled = try XCTUnwrap(notificationCenter.pending.values.first)
    let trigger = try XCTUnwrap(scheduled.trigger as? UNCalendarNotificationTrigger)
    XCTAssertEqual(trigger.dateComponents.weekday, Weekday.sunday.rawValue)
    XCTAssertEqual(trigger.dateComponents.hour, request.hour)
    XCTAssertEqual(trigger.dateComponents.minute, request.minute)
    XCTAssertNil(trigger.dateComponents.year)
    XCTAssertNil(trigger.dateComponents.month)
    XCTAssertNil(trigger.dateComponents.day)
    XCTAssertNil(trigger.dateComponents.timeZone)
  }

  func testReleaseSourcesExposeNoUnprovedAlarmKitParity() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let fileManager = FileManager.default
    let removedSurfaces = [
      "Moru/RoutineFlow/Alarm/AlarmRingView.swift",
      "Moru/RoutineFlow/Alarm/SnoozeSheetView.swift",
      "Moru/RoutineFlow/Alarm/Components/AlarmRoutineCardView.swift",
      "Moru/RoutineFlow/Alarm/Components/SlideToStartControl.swift",
    ]
    for path in removedSurfaces {
      XCTAssertFalse(fileManager.fileExists(atPath: projectRoot.appendingPathComponent(path).path))
    }

    let infoData = try Data(contentsOf: projectRoot.appendingPathComponent("Info.plist"))
    let info = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
    )
    XCTAssertNil(info["NSAlarmKitUsageDescription"])

    let schedulerSource = try String(
      contentsOf: projectRoot.appendingPathComponent(
        "Moru/Data/Platform/UserNotificationAlarmScheduler.swift"
      ),
      encoding: .utf8
    )
    XCTAssertFalse(schedulerSource.contains("import AlarmKit"))
    XCTAssertFalse(schedulerSource.contains("categoryIdentifier"))
    XCTAssertFalse(schedulerSource.contains("AppIntent"))
  }

  func testSchedulerDuplicateReplaceRemainsIdempotent() async throws {
    let notificationCenter = NotificationCenterSpy()
    let scheduler = UserNotificationAlarmScheduler(notificationCenter: notificationCenter)
    let scheduleID = uuid("00000000-0000-0000-0000-000000000010")
    let request = makeRequest(scheduleID: scheduleID, weekdays: [.sunday, .wednesday])

    try await scheduler.replace(request)
    try await scheduler.replace(request)

    XCTAssertEqual(notificationCenter.addAttempts, 4)
    XCTAssertEqual(
      Set(notificationCenter.pending.keys),
      Set([
        UserNotificationAlarmScheduler.requestIdentifier(scheduleID: scheduleID, weekday: .sunday),
        UserNotificationAlarmScheduler.requestIdentifier(
          scheduleID: scheduleID,
          weekday: .wednesday
        )
      ])
    )
    XCTAssertEqual(notificationCenter.removePendingCalls.count, 2)
    XCTAssertTrue(
      notificationCenter.removePendingCalls.allSatisfy {
        $0 == UserNotificationAlarmScheduler.requestIdentifiers(scheduleID: scheduleID)
      }
    )
  }

  func testSchedulerRollsBackAllIdentifiersAfterPartialAddFailure() async {
    let notificationCenter = NotificationCenterSpy()
    notificationCenter.failOnAddAttempt = 2
    let scheduler = UserNotificationAlarmScheduler(notificationCenter: notificationCenter)
    let scheduleID = uuid("00000000-0000-0000-0000-000000000020")
    let request = makeRequest(scheduleID: scheduleID, weekdays: [.monday, .tuesday])

    do {
      try await scheduler.replace(request)
      XCTFail("A partial add failure must be propagated.")
    } catch {
      XCTAssertEqual(notificationCenter.addAttempts, 2)
      XCTAssertTrue(notificationCenter.pending.isEmpty)
      XCTAssertEqual(
        notificationCenter.removePendingCalls.last,
        UserNotificationAlarmScheduler.requestIdentifiers(scheduleID: scheduleID)
      )
      XCTAssertEqual(
        notificationCenter.removeDeliveredCalls.last,
        UserNotificationAlarmScheduler.requestIdentifiers(scheduleID: scheduleID)
      )
    }
  }
  func testFingerprintIsDeterministicSHA256ForNormalizedScheduleValues() {
    let routineID = uuid("00000000-0000-0000-0000-000000000030")
    let scheduleID = uuid("00000000-0000-0000-0000-000000000031")
    let first = AlarmNotificationScheduleRequest.desiredScheduleFingerprint(
      routineID: routineID,
      scheduleID: scheduleID,
      routineName: "아침 루틴",
      hour: 7,
      minute: 30,
      weekdays: [.friday, .monday],
      resetGeneration: 7
    )
    let reordered = AlarmNotificationScheduleRequest.desiredScheduleFingerprint(
      routineID: routineID,
      scheduleID: scheduleID,
      routineName: "아침 루틴",
      hour: 7,
      minute: 30,
      weekdays: [.monday, .friday],
      resetGeneration: 7
    )
    let changed = AlarmNotificationScheduleRequest.desiredScheduleFingerprint(
      routineID: routineID,
      scheduleID: scheduleID,
      routineName: "아침 루틴",
      hour: 7,
      minute: 31,
      weekdays: [.monday, .friday],
      resetGeneration: 7
    )

    XCTAssertEqual(first, reordered)
    XCTAssertNotEqual(first, changed)
    XCTAssertEqual(first.count, 64)
    XCTAssertTrue(first.allSatisfy { $0.isHexDigit && !$0.isUppercase })
  }

  func testScheduleValidationRejectsOutOfRangeAndAmbiguousWeekdays() {
    XCTAssertEqual(
      AlarmNotificationScheduleRequest.validationError(
        hour: 7,
        minute: 60,
        weekdays: [.monday]
      ),
      .invalidMinute(60)
    )
    XCTAssertEqual(
      AlarmNotificationScheduleRequest.validationError(
        hour: 7,
        minute: 30,
        weekdays: []
      ),
      .emptyWeekdays
    )
    XCTAssertEqual(
      AlarmNotificationScheduleRequest.validationError(
        hour: 7,
        minute: 30,
        weekdays: [.monday, .monday]
      ),
      .duplicateWeekdays
    )
  }

  func testCommitFailsWithoutSchedulingWhenPermissionIsDenied() async {
    let scheduler = AlarmSchedulerSpy()
    scheduler.authorization = .denied
    let repository = AlarmPlatformRepositorySpy()
    let coordinator = makeCoordinator(scheduler: scheduler, repository: repository)
    let routine = makeRoutine()
    let scheduleID = routine.alarmSchedule!.id

    do {
      try await coordinator.commit(routines: [routine], localCommit: {})
      XCTFail("A denied notification permission must fail the mutation.")
    } catch let error as NotificationAlarmMutationError {
      XCTAssertEqual(error, .permissionDenied)
      XCTAssertTrue(scheduler.replaceRequests.isEmpty)
      XCTAssertEqual(repository.snapshots[scheduleID]?.state, .repairRequired)
      XCTAssertEqual(
        repository.snapshots[scheduleID]?.lastErrorCode,
        "notificationPermissionDenied"
      )
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testCommitPreservesRequestIDForSameFingerprintAndReplacesItWhenChanged() async throws {
    let scheduler = AlarmSchedulerSpy()
    let repository = AlarmPlatformRepositorySpy()
    let requestIDs = UUIDFactory([
      uuid("00000000-0000-0000-0000-000000000101"),
      uuid("00000000-0000-0000-0000-000000000102")
    ])
    let coordinator = makeCoordinator(
      scheduler: scheduler,
      repository: repository,
      makeUUID: { requestIDs.next() }
    )
    var routine = makeRoutine()

    try await coordinator.commit(routines: [routine], localCommit: {})
    let firstRequestID = try XCTUnwrap(
      repository.snapshots[routine.alarmSchedule!.id]?.platformRequestID
    )

    try await coordinator.commit(routines: [routine], localCommit: {})
    XCTAssertEqual(
      repository.snapshots[routine.alarmSchedule!.id]?.platformRequestID,
      firstRequestID
    )

    routine.alarmSchedule?.hour = 8
    try await coordinator.commit(routines: [routine], localCommit: {})
    XCTAssertNotEqual(
      repository.snapshots[routine.alarmSchedule!.id]?.platformRequestID,
      firstRequestID
    )
    XCTAssertEqual(requestIDs.nextCallCount, 2)
  }

  func testLocalCommitFailureLeavesSchedulingStateRepairRequired() async {
    let scheduler = AlarmSchedulerSpy()
    let repository = AlarmPlatformRepositorySpy()
    let coordinator = makeCoordinator(scheduler: scheduler, repository: repository)
    let routine = makeRoutine()

    do {
      try await coordinator.commit(routines: [routine], localCommit: {
        throw TestFailure.forced
      })
      XCTFail("A local commit failure must be propagated.")
    } catch let error as NotificationAlarmMutationError {
      XCTAssertEqual(error, .localCommitFailure)
      XCTAssertEqual(repository.snapshots[routine.alarmSchedule!.id]?.state, .repairRequired)
      XCTAssertEqual(scheduler.replaceRequests.count, 1)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testCommitSchedulesRoutinesInStableIdentifierOrder() async throws {
    let scheduler = AlarmSchedulerSpy()
    let repository = AlarmPlatformRepositorySpy()
    let coordinator = makeCoordinator(scheduler: scheduler, repository: repository)
    let firstRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000001"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000011")
    )
    let secondRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000002"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000012")
    )

    try await coordinator.commit(
      routines: [secondRoutine, firstRoutine],
      localCommit: {}
    )

    XCTAssertEqual(scheduler.replaceRequests.map(\.routineID), [firstRoutine.id, secondRoutine.id])
  }

  func testDisabledScheduleIsCancelledWithoutRequestingPermission() async throws {
    let scheduler = AlarmSchedulerSpy()
    let repository = AlarmPlatformRepositorySpy()
    let coordinator = makeCoordinator(scheduler: scheduler, repository: repository)
    let routine = makeRoutine(isEnabled: false)
    let scheduleID = try XCTUnwrap(routine.alarmSchedule?.id)

    try await coordinator.commit(routines: [routine], localCommit: {})

    XCTAssertEqual(scheduler.cancelledScheduleIDs, [scheduleID])
    XCTAssertTrue(scheduler.replaceRequests.isEmpty)
    XCTAssertEqual(scheduler.authorizationStateCallCount, 0)
    XCTAssertEqual(repository.snapshots[scheduleID]?.state, .cancelled)
  }

  func testInvalidScheduleFailsBeforePlatformOrLocalMutation() async {
    let scheduler = AlarmSchedulerSpy()
    let repository = AlarmPlatformRepositorySpy()
    let localCommitCounter = CallCounter()
    let coordinator = makeCoordinator(scheduler: scheduler, repository: repository)
    let routine = makeRoutine(hour: 24)

    do {
      try await coordinator.commit(routines: [routine], localCommit: {
        localCommitCounter.increment()
      })
      XCTFail("An invalid alarm time must fail the mutation.")
    } catch let error as NotificationAlarmMutationError {
      XCTAssertEqual(error, .invalidSchedule)
      XCTAssertTrue(scheduler.replaceRequests.isEmpty)
      XCTAssertTrue(repository.snapshots.isEmpty)
      XCTAssertEqual(localCommitCounter.count, 0)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testCancellationFailureLeavesCancellationPendingAndSkipsLocalCommit() async throws {
    let scheduler = AlarmSchedulerSpy()
    let repository = AlarmPlatformRepositorySpy()
    let localCommitCounter = CallCounter()
    let coordinator = makeCoordinator(scheduler: scheduler, repository: repository)
    let routine = makeRoutine()
    let scheduleID = try XCTUnwrap(routine.alarmSchedule?.id)

    try await coordinator.commit(routines: [routine], localCommit: {})
    scheduler.cancelError = TestFailure.forced

    do {
      try await coordinator.delete(
        routineID: routine.id,
        scheduleID: scheduleID,
        localCommit: { localCommitCounter.increment() }
      )
      XCTFail("A cancellation failure must be propagated.")
    } catch let error as NotificationAlarmMutationError {
      XCTAssertEqual(error, .platformFailure)
      XCTAssertEqual(repository.snapshots[scheduleID]?.state, .cancellationPending)
      XCTAssertEqual(localCommitCounter.count, 0)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testNormalMutationsDoNotInterleaveAcrossSchedulerAwait() async throws {
    let scheduler = AlarmSchedulerSpy()
    let repository = AlarmPlatformRepositorySpy()
    let coordinator = makeCoordinator(scheduler: scheduler, repository: repository)
    let replaceEntered = AsyncSignal()
    let resumeReplace = AsyncSignal()
    let blocker = CallCounter()
    let firstRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000401"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000411")
    )
    let secondRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000402"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000412")
    )
    scheduler.onReplace = { _ in
      guard blocker.count == 0 else {
        return
      }

      blocker.increment()
      await replaceEntered.signal()
      await resumeReplace.wait()
    }

    let firstTask = Task { @MainActor in
      try await coordinator.commit(routines: [firstRoutine], localCommit: {})
    }
    await replaceEntered.wait()

    let secondTask = Task { @MainActor in
      try await coordinator.commit(routines: [secondRoutine], localCommit: {})
    }
    await Task.yield()
    XCTAssertEqual(scheduler.replaceRequests.map(\.scheduleID), [firstRoutine.alarmSchedule!.id])

    await resumeReplace.signal()
    try await firstTask.value
    try await secondTask.value
    XCTAssertEqual(
      scheduler.replaceRequests.map(\.scheduleID),
      [firstRoutine.alarmSchedule!.id, secondRoutine.alarmSchedule!.id]
    )
  }
  func testQueuedMutationRevalidatesJournalAdmissionBeforeExecution() async throws {
    let scheduler = AlarmSchedulerSpy()
    let repository = AlarmPlatformRepositorySpy()
    let replaceEntered = AsyncSignal()
    let resumeReplace = AsyncSignal()
    let admissionChecks = CallCounter()
    let denialGate = CallCounter()
    let coordinator = makeCoordinator(
      scheduler: scheduler,
      repository: repository,
      mutationAllowed: {
        admissionChecks.increment()
        return denialGate.count == 0
      }
    )
    let firstRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000403"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000413")
    )
    let secondRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000404"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000414")
    )
    scheduler.onReplace = { _ in
      await replaceEntered.signal()
      await resumeReplace.wait()
    }

    let firstTask = Task { @MainActor in
      try await coordinator.commit(routines: [firstRoutine], localCommit: {})
    }
    await replaceEntered.wait()

    let secondTask = Task { @MainActor () -> NotificationAlarmMutationError? in
      do {
        try await coordinator.commit(routines: [secondRoutine], localCommit: {})
        return nil
      } catch {
        return error as? NotificationAlarmMutationError
      }
    }
    for _ in 0..<10 where admissionChecks.count < 2 {
      await Task.yield()
    }
    XCTAssertEqual(admissionChecks.count, 2)

    denialGate.increment()
    await resumeReplace.signal()

    try await firstTask.value
    let secondError = await secondTask.value
    XCTAssertEqual(secondError, .mutationFrozen)
    XCTAssertEqual(admissionChecks.count, 3)
    XCTAssertEqual(
      scheduler.replaceRequests.map(\.scheduleID),
      [firstRoutine.alarmSchedule!.id]
    )
  }

  func testFreezeDrainsActiveMutationAndRejectsQueuedNormalWork() async throws {
    let scheduler = AlarmSchedulerSpy()
    let repository = AlarmPlatformRepositorySpy()
    let coordinator = makeCoordinator(scheduler: scheduler, repository: repository)
    let replaceEntered = AsyncSignal()
    let resumeReplace = AsyncSignal()
    let blocker = CallCounter()
    let freezeCompletion = CallCounter()
    let routine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000421"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000431")
    )
    scheduler.onReplace = { _ in
      guard blocker.count == 0 else {
        return
      }

      blocker.increment()
      await replaceEntered.signal()
      await resumeReplace.wait()
    }

    let activeTask = Task { @MainActor in
      try await coordinator.commit(routines: [routine], localCommit: {})
    }
    await replaceEntered.wait()

    let queuedTask = Task { @MainActor () -> NotificationAlarmMutationError? in
      do {
        try await coordinator.reconcile(routines: [])
        return nil
      } catch {
        return error as? NotificationAlarmMutationError
      }
    }
    await Task.yield()

    let freezeTask = Task { @MainActor in
      let token = try await coordinator.freezeAndDrain()
      freezeCompletion.increment()
      return token
    }

    let queuedError = await queuedTask.value
    XCTAssertEqual(queuedError, .mutationFrozen)
    XCTAssertEqual(freezeCompletion.count, 0)
    XCTAssertEqual(scheduler.replaceRequests.map(\.scheduleID), [routine.alarmSchedule!.id])

    await resumeReplace.signal()
    try await activeTask.value
    let token = try await freezeTask.value
    XCTAssertEqual(freezeCompletion.count, 1)

    do {
      try await coordinator.reconcile(routines: [])
      XCTFail("Normal mutations must fail while a reset holds the freeze.")
    } catch let error as NotificationAlarmMutationError {
      XCTAssertEqual(error, .mutationFrozen)
    }

    coordinator.thaw(token)
  }

  func testFreezeTokenRejectsWrongOwnerAndAuthorizesCancellation() async throws {
    let scheduler = AlarmSchedulerSpy()
    let repository = AlarmPlatformRepositorySpy()
    let coordinator = makeCoordinator(scheduler: scheduler, repository: repository)
    let routine = makeRoutine()
    let scheduleID = try XCTUnwrap(routine.alarmSchedule?.id)

    try await coordinator.commit(routines: [routine], localCommit: {})
    let token = try await coordinator.freezeAndDrain()
    let wrongToken = AlarmMutationFreezeToken(
      id: uuid("00000000-0000-0000-0000-000000000441")
    )

    do {
      try await coordinator.cancelAll(scheduleIDs: [scheduleID], using: wrongToken)
      XCTFail("A different freeze token must not cancel schedules.")
    } catch let error as NotificationAlarmMutationError {
      XCTAssertEqual(error, .mutationFrozen)
    }
    XCTAssertTrue(scheduler.cancelledScheduleIDs.isEmpty)
    do {
      try await coordinator.commit(routines: [routine], localCommit: {})
      XCTFail("Commit must fail while a reset holds the freeze.")
    } catch let error as NotificationAlarmMutationError {
      XCTAssertEqual(error, .mutationFrozen)
    }

    do {
      try await coordinator.delete(
        routineID: routine.id,
        scheduleID: scheduleID,
        localCommit: {}
      )
      XCTFail("Delete must fail while a reset holds the freeze.")
    } catch let error as NotificationAlarmMutationError {
      XCTAssertEqual(error, .mutationFrozen)
    }

    coordinator.thaw(wrongToken)
    do {
      try await coordinator.reconcile(routines: [])
      XCTFail("A different freeze token must not release the mutation gate.")
    } catch let error as NotificationAlarmMutationError {
      XCTAssertEqual(error, .mutationFrozen)
    }

    try await coordinator.cancelAll(scheduleIDs: [scheduleID], using: token)
    XCTAssertEqual(repository.snapshots[scheduleID]?.state, .cancelled)
    coordinator.thaw(token)
  }

  func testMalformedDisabledAndInactiveSchedulesAreCancelled() async throws {
    let scheduler = AlarmSchedulerSpy()
    let repository = AlarmPlatformRepositorySpy()
    let coordinator = makeCoordinator(scheduler: scheduler, repository: repository)
    let disabledRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000451"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000461"),
      hour: 24,
      weekdays: [],
      isEnabled: false
    )
    let inactiveRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000452"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000462"),
      hour: 24,
      weekdays: [],
      isActive: false
    )

    try await coordinator.commit(
      routines: [inactiveRoutine, disabledRoutine],
      localCommit: {}
    )

    XCTAssertEqual(
      scheduler.cancelledScheduleIDs,
      [disabledRoutine.alarmSchedule!.id, inactiveRoutine.alarmSchedule!.id]
    )
    XCTAssertTrue(scheduler.replaceRequests.isEmpty)
    XCTAssertEqual(scheduler.authorizationStateCallCount, 0)
    XCTAssertEqual(repository.snapshots[disabledRoutine.alarmSchedule!.id]?.state, .cancelled)
    XCTAssertEqual(repository.snapshots[inactiveRoutine.alarmSchedule!.id]?.state, .cancelled)
  }

  func testPartialBatchFailureCompensatesAppliedReplacementsAndSkipsLocalCommit() async {
    let scheduler = AlarmSchedulerSpy()
    scheduler.replaceErrorOnAttempt = 2
    let repository = AlarmPlatformRepositorySpy()
    let localCommitCounter = CallCounter()
    let coordinator = makeCoordinator(scheduler: scheduler, repository: repository)
    let firstRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000471"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000481")
    )
    let secondRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000472"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000482")
    )

    do {
      try await coordinator.commit(
        routines: [secondRoutine, firstRoutine],
        localCommit: { localCommitCounter.increment() }
      )
      XCTFail("A later platform failure must fail the batch.")
    } catch let error as NotificationAlarmMutationError {
      XCTAssertEqual(error, .platformFailure)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(scheduler.replaceRequests.map(\.scheduleID), [firstRoutine.alarmSchedule!.id])
    XCTAssertEqual(scheduler.cancelledScheduleIDs, [firstRoutine.alarmSchedule!.id])
    XCTAssertEqual(localCommitCounter.count, 0)
    XCTAssertEqual(repository.snapshots[firstRoutine.alarmSchedule!.id]?.state, .repairRequired)
    XCTAssertEqual(repository.snapshots[secondRoutine.alarmSchedule!.id]?.state, .repairRequired)
    XCTAssertEqual(
      repository.snapshots[firstRoutine.alarmSchedule!.id]?.lastErrorCode,
      "notificationPlatformFailed"
    )
  }

  func testCompensationFailureIsRecordedWithoutClearingRepairEvidence() async {
    let scheduler = AlarmSchedulerSpy()
    scheduler.replaceErrorOnAttempt = 2
    scheduler.cancelErrorOnAttempt = 1
    let repository = AlarmPlatformRepositorySpy()
    let coordinator = makeCoordinator(scheduler: scheduler, repository: repository)
    let firstRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000491"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000501")
    )
    let secondRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000492"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000502")
    )

    do {
      try await coordinator.commit(routines: [firstRoutine, secondRoutine], localCommit: {})
      XCTFail("A later platform failure must trigger compensation.")
    } catch let error as NotificationAlarmMutationError {
      XCTAssertEqual(error, .platformFailure)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(repository.snapshots[firstRoutine.alarmSchedule!.id]?.state, .repairRequired)
    XCTAssertEqual(
      repository.snapshots[firstRoutine.alarmSchedule!.id]?.lastErrorCode,
      "notificationCompensationFailed"
    )
  }
  func testPersistenceFailureCannotSuppressAppliedReplacementCompensation() async {
    let scheduler = AlarmSchedulerSpy()
    let repository = AlarmPlatformRepositorySpy()
    repository.failSavesStartingAtAttempt = 2
    let localCommitCounter = CallCounter()
    let coordinator = makeCoordinator(scheduler: scheduler, repository: repository)
    let firstRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000503"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000513")
    )
    let secondRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000504"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000514")
    )

    do {
      try await coordinator.commit(
        routines: [secondRoutine, firstRoutine],
        localCommit: { localCommitCounter.increment() }
      )
      XCTFail("A later persistence failure must fail and compensate the batch.")
    } catch let error as NotificationAlarmMutationError {
      XCTAssertEqual(error, .storageFailure)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(scheduler.replaceRequests.map(\.scheduleID), [
      firstRoutine.alarmSchedule!.id
    ])
    XCTAssertEqual(scheduler.cancelledScheduleIDs, [
      firstRoutine.alarmSchedule!.id
    ])
    XCTAssertEqual(localCommitCounter.count, 0)
    XCTAssertGreaterThanOrEqual(repository.saveAttemptCount, 3)
  }

  func testUnavailableResetGenerationFailsBeforePlatformAndLocalMutation() async {
    let scheduler = AlarmSchedulerSpy()
    let repository = AlarmPlatformRepositorySpy()
    let localCommitCounter = CallCounter()
    let coordinator = makeCoordinator(
      scheduler: scheduler,
      repository: repository,
      resetGeneration: { throw TestFailure.forced }
    )

    do {
      try await coordinator.commit(
        routines: [makeRoutine()],
        localCommit: { localCommitCounter.increment() }
      )
      XCTFail("An unavailable reset generation must fail closed.")
    } catch let error as NotificationAlarmMutationError {
      XCTAssertEqual(error, .generationUnavailable)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertTrue(scheduler.replaceRequests.isEmpty)
    XCTAssertTrue(scheduler.cancelledScheduleIDs.isEmpty)
    XCTAssertEqual(localCommitCounter.count, 0)
    XCTAssertTrue(repository.snapshots.isEmpty)
  }

  func testLocalCommitFailureCompensatesAppliedReplacementsInReverseOrder() async {
    let scheduler = AlarmSchedulerSpy()
    let repository = AlarmPlatformRepositorySpy()
    let coordinator = makeCoordinator(scheduler: scheduler, repository: repository)
    let firstRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000511"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000521")
    )
    let secondRoutine = makeRoutine(
      routineID: uuid("00000000-0000-0000-0000-000000000512"),
      scheduleID: uuid("00000000-0000-0000-0000-000000000522")
    )

    do {
      try await coordinator.commit(
        routines: [secondRoutine, firstRoutine],
        localCommit: { throw TestFailure.forced }
      )
      XCTFail("A local commit failure must trigger compensation.")
    } catch let error as NotificationAlarmMutationError {
      XCTAssertEqual(error, .localCommitFailure)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(
      scheduler.cancelledScheduleIDs,
      [secondRoutine.alarmSchedule!.id, firstRoutine.alarmSchedule!.id]
    )
    XCTAssertEqual(repository.snapshots[firstRoutine.alarmSchedule!.id]?.state, .repairRequired)
    XCTAssertEqual(repository.snapshots[secondRoutine.alarmSchedule!.id]?.state, .repairRequired)
    XCTAssertEqual(
      repository.snapshots[firstRoutine.alarmSchedule!.id]?.lastErrorCode,
      "notificationLocalCommitFailed"
    )
    XCTAssertEqual(
      repository.snapshots[secondRoutine.alarmSchedule!.id]?.lastErrorCode,
      "notificationLocalCommitFailed"
    )
  }

  func testReconcileFinalizesConfiguredAndCancelledSnapshots() async throws {
    let scheduler = AlarmSchedulerSpy()
    let repository = AlarmPlatformRepositorySpy()
    let coordinator = makeCoordinator(scheduler: scheduler, repository: repository)
    let routine = makeRoutine()
    let scheduleID = try XCTUnwrap(routine.alarmSchedule?.id)

    try await coordinator.reconcile(routines: [routine])
    XCTAssertEqual(repository.snapshots[scheduleID]?.state, .configured)

    try await coordinator.reconcile(routines: [])
    XCTAssertEqual(repository.snapshots[scheduleID]?.state, .cancelled)
  }
  private func makeCoordinator(
    scheduler: AlarmSchedulerSpy,
    repository: AlarmPlatformRepositorySpy,
    resetGeneration: @escaping @MainActor () throws -> UInt64 = { 7 },
    mutationAllowed: @escaping @MainActor () -> Bool = { true },
    makeUUID: @escaping @MainActor () -> UUID = { UUID() }
  ) -> NotificationAlarmMutationCoordinator {
    NotificationAlarmMutationCoordinator(
      scheduler: scheduler,
      platformRepository: repository,
      resetGeneration: resetGeneration,
      mutationAllowed: mutationAllowed,
      now: { Date(timeIntervalSince1970: 1_000) },
      makeUUID: makeUUID
    )
  }

  private func makeRoutine(
    routineID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000100")!,
    scheduleID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000200")!,
    hour: Int = 7,
    minute: Int = 30,
    weekdays: [Weekday] = [.monday, .wednesday],
    isEnabled: Bool = true,
    isActive: Bool = true
  ) -> Routine {
    Routine(
      id: routineID,
      name: "아침 루틴",
      steps: [],
      alarmSchedule: AlarmSchedule(
        id: scheduleID,
        hour: hour,
        minute: minute,
        weekdays: weekdays,
        isEnabled: isEnabled
      ),
      isActive: isActive
    )
  }

  private func makeRequest(
    routineID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000300")!,
    scheduleID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000400")!,
    weekdays: [Weekday]
  ) -> AlarmNotificationScheduleRequest {
    AlarmNotificationScheduleRequest(
      routineID: routineID,
      scheduleID: scheduleID,
      routineName: "아침 루틴",
      hour: 7,
      minute: 30,
      weekdays: weekdays,
      resetGeneration: 7,
      desiredScheduleFingerprint: "fingerprint"
    )
  }

  private func uuid(_ value: String) -> UUID {
    UUID(uuidString: value)!
  }
}

private enum TestFailure: Error {
  case forced
}

private actor AsyncSignal {
  private var didSignal = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !didSignal else {
      return
    }

    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func signal() {
    guard !didSignal else {
      return
    }

    didSignal = true
    let pendingWaiters = waiters
    waiters.removeAll()

    for waiter in pendingWaiters {
      waiter.resume()
    }
  }
}

@MainActor
private final class NotificationCenterSpy: UserNotificationCenterScheduling {
  var authorization = UNAuthorizationStatus.authorized
  var authorizationGranted = true
  var failOnAddAttempt: Int?
  var addAttempts = 0
  var pending: [String: UNNotificationRequest] = [:]
  var removePendingCalls: [[String]] = []
  var removeDeliveredCalls: [[String]] = []

  func authorizationStatus() async -> UNAuthorizationStatus {
    authorization
  }

  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
    authorizationGranted
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
    removePendingCalls.append(identifiers)
    identifiers.forEach { pending.removeValue(forKey: $0) }
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
    removeDeliveredCalls.append(identifiers)
  }

  func add(_ request: UNNotificationRequest) async throws {
    addAttempts += 1
    if failOnAddAttempt == addAttempts {
      throw TestFailure.forced
    }
    pending[request.identifier] = request
  }
}

@MainActor
private final class AlarmSchedulerSpy: AlarmNotificationScheduling {
  var authorization: AlarmNotificationPermissionState = .authorized
  var authorizationStateCallCount = 0
  var authorizationRequestCallCount = 0
  var replaceRequests: [AlarmNotificationScheduleRequest] = []
  var cancelledScheduleIDs: [UUID] = []
  var replaceError: Error?
  var replaceErrorOnAttempt: Int?
  var cancelError: Error?
  var cancelErrorOnAttempt: Int?
  var onReplace: (@MainActor (AlarmNotificationScheduleRequest) async -> Void)?
  private(set) var replaceAttemptCount = 0
  private(set) var cancelAttemptCount = 0

  func authorizationState() async -> AlarmNotificationPermissionState {
    authorizationStateCallCount += 1
    return authorization
  }

  func requestAuthorization() async throws -> AlarmNotificationPermissionState {
    authorizationRequestCallCount += 1
    return authorization
  }

  func replace(_ request: AlarmNotificationScheduleRequest) async throws {
    replaceAttemptCount += 1
    if let replaceError {
      throw replaceError
    }
    if replaceErrorOnAttempt == replaceAttemptCount {
      throw TestFailure.forced
    }

    replaceRequests.append(request)
    await onReplace?(request)
  }

  func cancel(scheduleID: UUID) async throws {
    cancelAttemptCount += 1
    if let cancelError {
      throw cancelError
    }
    if cancelErrorOnAttempt == cancelAttemptCount {
      throw TestFailure.forced
    }

    cancelledScheduleIDs.append(scheduleID)
  }
}

@MainActor
private final class AlarmPlatformRepositorySpy: AlarmPlatformStateRepository {
  var snapshots: [UUID: AlarmPlatformSnapshot] = [:]
  var error: Error?
  var failSavesStartingAtAttempt: Int?
  private(set) var saveAttemptCount = 0

  func fetchAll() throws -> [AlarmPlatformSnapshot] {
    if let error {
      throw error
    }
    return Array(snapshots.values)
  }

  func fetch(scheduleID: UUID) throws -> AlarmPlatformSnapshot? {
    if let error {
      throw error
    }
    return snapshots[scheduleID]
  }

  func save(_ snapshot: AlarmPlatformSnapshot) throws {
    saveAttemptCount += 1
    if let failSavesStartingAtAttempt,
       saveAttemptCount >= failSavesStartingAtAttempt {
      throw TestFailure.forced
    }
    if let error {
      throw error
    }
    snapshots[snapshot.scheduleID] = snapshot
  }
}

@MainActor
private final class UUIDFactory {
  private var values: [UUID]
  private(set) var nextCallCount = 0

  init(_ values: [UUID]) {
    self.values = values
  }

  func next() -> UUID {
    nextCallCount += 1
    return values.removeFirst()
  }
}

@MainActor
private final class CallCounter {
  private(set) var count = 0

  func increment() {
    count += 1
  }
}
