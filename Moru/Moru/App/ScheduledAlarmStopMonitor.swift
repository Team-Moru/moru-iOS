//
//  ScheduledAlarmStopMonitor.swift
//  Moru
//

import Foundation
import Observation

/// AlarmKit 직접 진입(`launchTarget == .scheduledRoutine`)에서 알람을 언제 끌지 정한다.
/// 표시가 승인된 뒤에만 끈다. `.deferredBusy`는 아무것도 표시되지 않았으므로 끄지 않는다 —
/// 부활 경로(`retryDeferredAlarmIngressOrOnboarding`)가 같은 봉투로 다시 들어와 그때 끈다.
enum ScheduledAlarmStopPolicy {
  enum Action: Equatable {
    case `defer`
    case completeAndStop(presentationToken: UUID)
  }

  static func action(for attempt: PresentationAttempt) -> Action {
    switch attempt {
    case .deferredBusy:
      return .defer
    case .presented(let token), .alreadyPresented(let token):
      return .completeAndStop(presentationToken: token)
    }
  }
}

/// 직접 진입한 플레이어 위에서 알람 정지의 진행·실패를 추적한다.
/// 실패하면 플레이어 상단 배너가 재시도를 제공한다. 플레이어 코드는 이 타입을 모른다.
@MainActor
@Observable
final class ScheduledAlarmStopMonitor {
  enum Phase: Equatable {
    case idle
    /// 표시 승인 직후의 첫 정지 시도. 배너는 띄우지 않는다.
    case stopping
    case failed
    /// 실패 뒤 사용자가 누른 재시도. 배너는 유지하고 버튼만 잠근다.
    case retrying
  }

  private(set) var phase: Phase = .idle
  private(set) var context: AlarmRingContext?
  private(set) var presentationToken: UUID?

  func begin(context: AlarmRingContext, presentationToken: UUID) {
    self.context = context
    self.presentationToken = presentationToken
    phase = .stopping
  }

  /// 실패한 정지를 다시 시도한다. 실패 상태가 아니면 아무것도 하지 않는다.
  func beginRetry() -> AlarmRingContext? {
    guard phase == .failed, let context else {
      return nil
    }

    phase = .retrying
    return context
  }

  func markStopped() {
    phase = .idle
    context = nil
    presentationToken = nil
  }

  func markFailed() {
    guard context != nil else {
      return
    }

    phase = .failed
  }

  func clear() {
    phase = .idle
    context = nil
    presentationToken = nil
  }

  /// 이 표시 토큰의 플레이어 위에 재시도 배너를 보여야 하는가
  func showsRetryBanner(for token: UUID) -> Bool {
    guard presentationToken == token else {
      return false
    }

    return phase == .failed || phase == .retrying
  }

  var isRetrying: Bool {
    phase == .retrying
  }
}
