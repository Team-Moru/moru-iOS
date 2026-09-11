//
//  AlarmIngressDriver.swift
//  Moru
//

import Foundation
import OSLog

/// 알람 봉투를 받아 해석하고, 표시가 승인된 뒤에 알람을 끄는 일만 맡는다.
///
/// 예전에는 이 로직이 전부 `AppRouter`의 private 메서드였다. AlarmKit 직행 규칙
/// (`launchTarget == .scheduledRoutine`)이 View 안에만 있어 알람 동작을 고치려면
/// 화면을 고쳐야 했고, 라우터를 View로 세우는 테스트가 없어 직접 검증할 수도 없었다.
@MainActor
final class AlarmIngressDriver {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Moru",
    category: "AlarmRuntime"
  )

  private let alarmRuntimeHandler: (any AlarmRuntimeHandling)?
  private let coordinator: AppNavigationCoordinator
  private let alarmStopMonitor: ScheduledAlarmStopMonitor
  private let occurrenceStore: AlarmIngressOccurrenceStore

  init(
    alarmRuntimeHandler: (any AlarmRuntimeHandling)?,
    coordinator: AppNavigationCoordinator,
    alarmStopMonitor: ScheduledAlarmStopMonitor,
    occurrenceStore: AlarmIngressOccurrenceStore = .shared
  ) {
    self.alarmRuntimeHandler = alarmRuntimeHandler
    self.coordinator = coordinator
    self.alarmStopMonitor = alarmStopMonitor
    self.occurrenceStore = occurrenceStore
  }

  // MARK: - Ingress

  func consumePendingIngress(
    sessionPhase: SessionStore.Phase,
    accountState: AccountSessionState
  ) async {
    if case .restoring = accountState {
      return
    }

    await consumePendingIngressAfterAccountRestoration(sessionPhase: sessionPhase)
  }

  func consumePendingIngressAfterAccountRestoration(
    sessionPhase: SessionStore.Phase
  ) async {
    guard sessionPhase == .ready,
          alarmRuntimeHandler != nil,
          let envelope = occurrenceStore.claimPendingEnvelope() else {
      return
    }

    await handle(envelope)
  }

  func handle(_ envelope: AlarmIngressEnvelope) async {
    guard let alarmRuntimeHandler else {
      occurrenceStore.release(envelope)
      return
    }

    switch await alarmRuntimeHandler.resolve(envelope) {
    case .route(let context):
      await presentResolved(context)
    case .ignored:
      occurrenceStore.complete(envelope)
    case .temporarilyUnavailable:
      occurrenceStore.release(envelope)
    }
  }

  /// 미뤄 둔 알람을 다시 시도한다. 처리할 알람이 없으면 false를 돌려주고,
  /// 호출자가 온보딩 체험 복원 같은 다음 후보로 넘어간다.
  func retryDeferredIngress() async -> Bool {
    guard let context = coordinator.takeDeferredAlarmContext() else {
      return false
    }

    await handle(context.ingress)
    return coordinator.presentation != nil
  }

  private func presentResolved(_ context: AlarmRingContext) async {
    guard context.ingress.launchTarget == .scheduledRoutine else {
      switch coordinator.presentAlarmRing(context: context) {
      case .presented, .alreadyPresented:
        occurrenceStore.complete(context.ingress)
      case .deferredBusy:
        break
      }
      return
    }

    let attempt = coordinator.presentScheduledRoutine(context: context)

    // 알람은 플레이어 표시가 승인된 뒤에만 끈다. 미뤄진 경우는 부활 경로가 다시 들어온다.
    switch ScheduledAlarmStopPolicy.action(for: attempt) {
    case .defer:
      Self.logger.info("scheduled_player_deferred_busy")
    case .completeAndStop(let presentationToken):
      if case .alreadyPresented = attempt {
        Self.logger.info("scheduled_player_already_presented")
      } else {
        Self.logger.info("scheduled_player_presented")
      }
      occurrenceStore.complete(context.ingress)
      stopWithoutBlockingRoutinePresentation(
        context,
        presentationToken: presentationToken
      )
    }
  }

  // MARK: - Stopping

  private func stopWithoutBlockingRoutinePresentation(
    _ context: AlarmRingContext,
    presentationToken: UUID
  ) {
    guard alarmRuntimeHandler != nil else {
      return
    }

    alarmStopMonitor.begin(context: context, presentationToken: presentationToken)
    performStop(context)
  }

  /// 플레이어 상단 배너의 재시도. 정지 실패는 로그로 끝나지 않고 사용자에게 돌아온다.
  func retryStop() {
    guard let context = alarmStopMonitor.beginRetry() else {
      return
    }

    performStop(context)
  }

  private func performStop(_ context: AlarmRingContext) {
    guard let alarmRuntimeHandler else {
      alarmStopMonitor.markFailed()
      return
    }

    let monitor = alarmStopMonitor
    Task { @MainActor in
      do {
        try await alarmRuntimeHandler.stopAlarm(for: context)
        monitor.markStopped()
        Self.logger.info("scheduled_player_alarm_stop_succeeded")
      } catch {
        monitor.markFailed()
        Self.logger.error("scheduled_player_alarm_stop_failed")
      }
    }
  }

  // MARK: - Ring actions

  func startScheduledRoutine(
    from context: AlarmRingContext,
    presentationToken: UUID
  ) async throws {
    guard let alarmRuntimeHandler else {
      throw AlarmRuntimeError.routeNoLongerAvailable
    }

    try await alarmRuntimeHandler.stopAlarm(for: context)
    guard coordinator.startScheduledRoutine(
      routineID: context.ingress.routineID,
      alarmPresentationToken: presentationToken
    ) else {
      throw AlarmRuntimeError.routeNoLongerAvailable
    }
  }

  /// 스누즈 후 링을 닫는 효과를 돌려준다. 효과 실행은 라우터가 맡는다.
  func snooze(
    context: AlarmRingContext,
    minutes: Int,
    presentationToken: UUID
  ) async throws -> AppNavigationEffect {
    guard let alarmRuntimeHandler else {
      throw AlarmRuntimeError.routeNoLongerAvailable
    }

    _ = try await alarmRuntimeHandler.snooze(
      context: context,
      minutes: minutes
    )
    return coordinator.dismissAlarmRing(presentationToken: presentationToken)
  }
}
