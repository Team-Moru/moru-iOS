//
//  VoiceInputControlView.swift
//  Moru
//

import SwiftUI
import UIKit

enum SpeechNoInputAction: Equatable {
  case playReminder
  case automaticSkip
}

struct SpeechNoInputSequence: Equatable {
  private(set) var didPlayReminder = false

  mutating func actionForTimeout() -> SpeechNoInputAction {
    guard didPlayReminder else {
      didPlayReminder = true
      return .playReminder
    }

    return .automaticSkip
  }

  mutating func speechWasDetected() {
    didPlayReminder = false
  }
}

struct VoiceInputControlView: View {
  private enum AutomaticStartState {
    case waitingForGuidance
    case ready
    case started
    case manualOnly
  }

  let speechInputController: SpeechInputController
  let automaticCompletionIntent: SpeechAutomaticCompletionIntent?
  let autoFinishMatch: ((String) -> RoutineStepCompletionMatch)?
  let showsTranscript: Bool
  let isAutomaticStartBlocked: Bool
  let waitUntilGuidanceFinishes: () async -> Bool
  let onNoSpeechReminder: () async -> Bool
  let onAutomaticSkip: () -> Void
  /// 음성 인식이 영구 실패했을 때 손으로 단계를 끝내는 경로. nil이면 버튼을 숨긴다.
  let onManualComplete: (() -> Void)?
  let onFinished: (String) -> Void
  private let appSettingsOpener: AppSettingsOpener
  @State private var isAutomaticallyFinishing = false
  @State private var automaticStartState: AutomaticStartState = .waitingForGuidance
  @State private var pendingAutomaticFinishTask: Task<Void, Never>?
  @State private var noInputSequence = SpeechNoInputSequence()
  @State private var noInputHandlingTask: Task<Void, Never>?
  /// 안내 대기 중에 백그라운드를 다녀오면 대기가 false로 끝나는데, 그 경우에도 자동 시작을 살린다.
  @State private var shouldResumeAfterInterruptedGuidance = false

  init(
    speechInputController: SpeechInputController,
    automaticCompletionIntent: SpeechAutomaticCompletionIntent? = nil,
    autoFinishMatch: ((String) -> RoutineStepCompletionMatch)? = nil,
    showsTranscript: Bool = true,
    isAutomaticStartBlocked: Bool = false,
    waitUntilGuidanceFinishes: @escaping () async -> Bool = { true },
    onNoSpeechReminder: @escaping () async -> Bool = { true },
    onAutomaticSkip: @escaping () -> Void = {},
    onManualComplete: (() -> Void)? = nil,
    appSettingsOpener: AppSettingsOpener = AppSettingsOpener(),
    onFinished: @escaping (String) -> Void
  ) {
    self.speechInputController = speechInputController
    self.automaticCompletionIntent = automaticCompletionIntent
    self.autoFinishMatch = autoFinishMatch
    self.showsTranscript = showsTranscript
    self.isAutomaticStartBlocked = isAutomaticStartBlocked
    self.waitUntilGuidanceFinishes = waitUntilGuidanceFinishes
    self.onNoSpeechReminder = onNoSpeechReminder
    self.onAutomaticSkip = onAutomaticSkip
    self.onManualComplete = onManualComplete
    self.appSettingsOpener = appSettingsOpener
    self.onFinished = onFinished
  }

  var body: some View {
    VStack(spacing: 16) {
      if speechInputController.isPreparing {
        preparingView
      } else if speechInputController.shouldShowControls {
        recognitionControlView
      } else if noInputHandlingTask != nil {
        noSpeechReminderView
      } else if case .failed = speechInputController.phase {
        failureView
      } else if automaticStartState == .waitingForGuidance {
        guidanceWaitingView
      } else {
        VoiceMicButton {
          Task {
            await speechInputController.start()
          }
        }
      }
    }
    .onDisappear {
      cancelPendingAutomaticFinish()
      noInputHandlingTask?.cancel()
      noInputHandlingTask = nil
      speechInputController.cancel()
    }
    .task {
      guard automaticStartState == .waitingForGuidance else {
        return
      }

      let guidanceDidFinish = await waitUntilGuidanceFinishes()
      guard !Task.isCancelled else {
        return
      }

      let resumesAfterInterruption = shouldResumeAfterInterruptedGuidance
      shouldResumeAfterInterruptedGuidance = false
      automaticStartState = guidanceDidFinish || resumesAfterInterruption ? .ready : .manualOnly
      await startAutomaticallyIfPossible()
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: UIApplication.willEnterForegroundNotification
      )
    ) { _ in
      resumeAutomaticStartAfterForeground()
    }
    .onChange(of: speechInputController.latestTranscriptUpdate) { _, update in
      if let update,
         !update.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        noInputSequence.speechWasDetected()
      }
      scheduleAutomaticFinishIfNeeded(for: update)
    }
    .onChange(of: speechInputController.phase) { _, phase in
      if phase == .failed(.silence) {
        handleNoSpeechTimeout()
      }

      guard phase != .listening else {
        return
      }

      cancelPendingAutomaticFinish()
    }
    .onChange(of: speechInputController.latestSilenceCompletion) { _, completion in
      finishAfterSilenceIfNeeded(completion)
    }
    .onChange(of: isAutomaticStartBlocked) { _, isBlocked in
      guard !isBlocked else {
        return
      }

      Task {
        await startAutomaticallyIfPossible()
      }
    }
  }

  private func startAutomaticallyIfPossible() async {
    guard automaticStartState == .ready,
          !isAutomaticStartBlocked,
          speechInputController.phase == .idle else {
      return
    }

    automaticStartState = .started
    await speechInputController.start()
  }

  /// 백그라운드 진입이 인식을 취소하면 `.started`/`.manualOnly`에 멈춰 자동 시작이 다시 오지 않는다.
  /// 복귀 시 안내 재생 없이 인식만 다시 켠다. 일시정지·실패 상태는 건드리지 않는다.
  private func resumeAutomaticStartAfterForeground() {
    switch automaticStartState {
    case .waitingForGuidance:
      shouldResumeAfterInterruptedGuidance = true

    case .started, .manualOnly:
      guard speechInputController.phase == .idle,
            !speechInputController.isPreparing else {
        return
      }

      automaticStartState = .ready
      Task {
        await startAutomaticallyIfPossible()
      }

    case .ready:
      break
    }
  }

  private func scheduleAutomaticFinishIfNeeded(for update: SpeechTranscriptUpdate?) {
    guard
      let update,
      let automaticCompletionIntent,
      !isAutomaticallyFinishing,
      speechInputController.phase == .listening
    else {
      cancelPendingAutomaticFinish()
      return
    }

    let match = autoFinishMatch?(update.text) ?? .none
    switch SpeechAutomaticCompletionPolicy.disposition(
      for: update,
      intent: automaticCompletionIntent,
      match: match
    ) {
    case .none:
      cancelPendingAutomaticFinish()

    case .immediately:
      cancelPendingAutomaticFinish()
      finishAutomatically(using: update.text)

    case .afterDelay(let delay):
      scheduleDeferredAutomaticFinish(for: update, after: delay)
    }
  }

  private func scheduleDeferredAutomaticFinish(
    for update: SpeechTranscriptUpdate,
    after delay: Duration
  ) {
    cancelPendingAutomaticFinish()

    pendingAutomaticFinishTask = Task { @MainActor in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }

      guard
        !Task.isCancelled,
        !isAutomaticallyFinishing,
        speechInputController.phase == .listening,
        speechInputController.latestTranscriptUpdate == update,
        let automaticCompletionIntent
      else {
        return
      }

      let match = autoFinishMatch?(update.text) ?? .none
      guard case .afterDelay = SpeechAutomaticCompletionPolicy.disposition(
        for: update,
        intent: automaticCompletionIntent,
        match: match
      ) else {
        return
      }

      finishAutomatically(using: update.text)
    }
  }

  private func finishAutomatically(using transcript: String) {
    guard !isAutomaticallyFinishing else {
      return
    }

    isAutomaticallyFinishing = true
    pendingAutomaticFinishTask = nil

    guard let finalTranscript = speechInputController.finishImmediately(using: transcript) else {
      isAutomaticallyFinishing = false
      return
    }

    onFinished(finalTranscript)
  }

  private func finishAfterSilenceIfNeeded(_ completion: SpeechSilenceCompletion?) {
    guard let completion,
          let automaticCompletionIntent,
          !isAutomaticallyFinishing else {
      return
    }

    switch automaticCompletionIntent {
    case .dictatedInput:
      guard !completion.transcript
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty else {
        return
      }

    case .stepCompletion:
      let update = SpeechTranscriptUpdate(
        text: completion.transcript,
        isFinal: true
      )
      let match = autoFinishMatch?(completion.transcript) ?? .none
      guard SpeechAutomaticCompletionPolicy.disposition(
        for: update,
        intent: automaticCompletionIntent,
        match: match
      ) != .none else {
        return
      }
    }

    isAutomaticallyFinishing = true
    cancelPendingAutomaticFinish()
    onFinished(completion.transcript)
  }

  private func handleNoSpeechTimeout() {
    guard noInputHandlingTask == nil else {
      return
    }

    switch noInputSequence.actionForTimeout() {
    case .playReminder:
      noInputHandlingTask = Task { @MainActor in
        let shouldResume = await onNoSpeechReminder()
        guard !Task.isCancelled,
              shouldResume,
              !isAutomaticStartBlocked else {
          noInputHandlingTask = nil
          return
        }

        await speechInputController.retry()
        noInputHandlingTask = nil
      }

    case .automaticSkip:
      cancelPendingAutomaticFinish()
      speechInputController.cancel()
      onAutomaticSkip()
    }
  }

  private func cancelPendingAutomaticFinish() {
    pendingAutomaticFinishTask?.cancel()
    pendingAutomaticFinishTask = nil
  }

  private var preparingView: some View {
    VStack(spacing: 12) {
      ProgressView()
        .tint(AppColor.orange250)

      Text(speechInputController.statusText)
        .font(AppFont.caption1SemiBold)
        .foregroundStyle(AppColor.gray350)
    }
    .frame(height: 76)
  }

  private var noSpeechReminderView: some View {
    VStack(spacing: 12) {
      ProgressView()
        .tint(AppColor.orange250)

      Text("다시 말할 수 있도록 안내하고 있어요.")
        .font(AppFont.caption1SemiBold)
        .foregroundStyle(AppColor.gray350)
        .multilineTextAlignment(.center)
    }
    .frame(height: 76)
  }

  private var guidanceWaitingView: some View {
    VoiceMicButton(isDisabled: true) {}
      .accessibilityLabel("음성 안내가 끝난 뒤 인식을 시작해요.")
      .accessibilityHint("안내가 끝나면 자동으로 음성 인식을 시작합니다")
      .frame(height: 76)
  }

  private var recognitionControlView: some View {
    VStack(spacing: 12) {
      if showsTranscript, !speechInputController.displayTranscript.isEmpty {
        Text(speechInputController.displayTranscript)
          .font(AppFont.label1NormalMedium)
          .foregroundStyle(AppColor.gray500)
          .multilineTextAlignment(.center)
          .accessibilityLabel("인식된 내용")
          .accessibilityValue(speechInputController.displayTranscript)
      }

      VoiceSendingBarView(
        phase: speechInputController.phase,
        waveformLevels: speechInputController.waveformLevels,
        onPauseResume: {
          cancelPendingAutomaticFinish()
          Task {
            if speechInputController.isPaused {
              await speechInputController.resume()
            } else {
              await speechInputController.pause()
            }
          }
        },
        onStop: {
          cancelPendingAutomaticFinish()
          Task {
            guard let transcript = await speechInputController.finish() else {
              return
            }

            onFinished(transcript)
          }
        }
      )
    }
  }

  @ViewBuilder
  private var failureView: some View {
    VStack(spacing: 12) {
      Text(speechInputController.statusText)
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.gray500)
        .multilineTextAlignment(.center)

      if speechInputController.permanentFailure != nil {
        // 재시도가 무의미한 실패. 완주 경로가 건너뛰기뿐이면 완수율이 0%로 고정되므로
        // 손으로 끝내는 큰 버튼을 준다.
        if let onManualComplete {
          MoruButton(RoutinePlayerCopy.manualCompletionTitle) {
            onManualComplete()
          }
          .padding(.top, 4)
        }

        if isMicrophonePermissionDenied {
          Button("설정 열기") {
            Task {
              await appSettingsOpener.open()
            }
          }
          .buttonStyle(.plain)
          .font(AppFont.label1NormalSemiBold)
          .foregroundStyle(AppColor.orange350)
        }
      } else {
        Button("다시 시도") {
          Task {
            await speechInputController.retry()
          }
        }
        .buttonStyle(.plain)
        .font(AppFont.label1NormalSemiBold)
        .foregroundStyle(AppColor.orange350)
      }
    }
  }

  private var isMicrophonePermissionDenied: Bool {
    guard case .failed(.microphonePermissionDenied) = speechInputController.phase else {
      return false
    }

    return true
  }
}
