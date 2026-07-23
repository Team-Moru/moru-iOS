//
//  VoiceInputControlView.swift
//  Moru
//

import SwiftUI
import UIKit

struct VoiceInputControlView: View {
  let speechInputController: SpeechInputController
  let automaticCompletionIntent: SpeechAutomaticCompletionIntent?
  let autoFinishMatch: ((String) -> RoutineStepCompletionMatch)?
  let onFinished: (String) -> Void
  @Environment(\.openURL) private var openURL
  @State private var isAutomaticallyFinishing = false
  @State private var hasStartedAutomatically = false
  @State private var pendingAutomaticFinishTask: Task<Void, Never>?

  init(
    speechInputController: SpeechInputController,
    automaticCompletionIntent: SpeechAutomaticCompletionIntent? = nil,
    autoFinishMatch: ((String) -> RoutineStepCompletionMatch)? = nil,
    onFinished: @escaping (String) -> Void
  ) {
    self.speechInputController = speechInputController
    self.automaticCompletionIntent = automaticCompletionIntent
    self.autoFinishMatch = autoFinishMatch
    self.onFinished = onFinished
  }

  var body: some View {
    VStack(spacing: 16) {
      if speechInputController.isPreparing {
        preparingView
      } else if speechInputController.shouldShowControls {
        recognitionControlView
      } else if case .failed = speechInputController.phase {
        failureView
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
      speechInputController.cancel()
    }
    .task {
      guard !hasStartedAutomatically else {
        return
      }

      hasStartedAutomatically = true
      await speechInputController.start()
    }
    .onChange(of: speechInputController.latestTranscriptUpdate) { _, update in
      scheduleAutomaticFinishIfNeeded(for: update)
    }
    .onChange(of: speechInputController.phase) { _, phase in
      guard phase != .listening else {
        return
      }

      cancelPendingAutomaticFinish()
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

  private var recognitionControlView: some View {
    VStack(spacing: 12) {
      if !speechInputController.displayTranscript.isEmpty {
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

      if isMicrophonePermissionDenied {
        Button("설정 열기") {
          guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
          }

          openURL(settingsURL)
        }
        .buttonStyle(.plain)
        .font(AppFont.label1NormalSemiBold)
        .foregroundStyle(AppColor.orange350)
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
