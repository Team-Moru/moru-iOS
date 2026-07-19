//
//  VoiceInputControlView.swift
//  Moru
//

import SwiftUI
import UIKit

struct VoiceInputControlView: View {
  let speechInputController: SpeechInputController
  let autoFinishWhen: ((String) -> Bool)?
  let onFinished: (String) -> Void
  @Environment(\.openURL) private var openURL
  @State private var isAutomaticallyFinishing = false
  @State private var hasStartedAutomatically = false

  init(
    speechInputController: SpeechInputController,
    autoFinishWhen: ((String) -> Bool)? = nil,
    onFinished: @escaping (String) -> Void
  ) {
    self.speechInputController = speechInputController
    self.autoFinishWhen = autoFinishWhen
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
      speechInputController.cancel()
    }
    .task {
      guard !hasStartedAutomatically else {
        return
      }

      hasStartedAutomatically = true
      await speechInputController.start()
    }
    .onChange(of: speechInputController.latestFinalTranscript) { _, transcript in
      automaticallyFinishIfNeeded(for: transcript)
    }
  }

  private func automaticallyFinishIfNeeded(for transcript: String) {
    guard
      let autoFinishWhen,
      !isAutomaticallyFinishing,
      speechInputController.phase == .listening,
      autoFinishWhen(transcript)
    else {
      return
    }

    isAutomaticallyFinishing = true
    Task {
      guard let finalTranscript = await speechInputController.finish() else {
        isAutomaticallyFinishing = false
        return
      }

      onFinished(finalTranscript)
    }
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
          Task {
            if speechInputController.isPaused {
              await speechInputController.resume()
            } else {
              await speechInputController.pause()
            }
          }
        },
        onStop: {
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
