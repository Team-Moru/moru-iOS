//
//  RoutinePlayerEscapeVisualTests.swift
//  MoruTests
//

import SwiftUI
import XCTest
@testable import Moru

/// 2단계(루틴 실행 탈출구·안전)에서 추가된 상태를 결정적으로 렌더한다.
/// 승인 기준선(after.png)은 두지 않는다 — 새 PNG를 리포에 넣지 않기로 했으므로
/// 결정성(같은 입력 → 같은 PNG)과 문구만 고정하고, 캡처는 검토용으로 출력한다.
@MainActor
final class RoutinePlayerEscapeVisualTests: XCTestCase {
  private enum CaptureState: String, CaseIterable {
    case saveFailureBanner = "save-failure-banner"
    case discardDialog = "discard-dialog"
    case closeDialog = "close-dialog"
    case transcriberUnavailableComplete = "transcriber-unavailable-complete"
    case microphoneDeniedComplete = "microphone-denied-complete"
    case alarmStopRetryBanner = "alarm-stop-retry-banner"
  }

  func testAlarmStopRetryBannerCopyExplainsThatTheRoutineContinues() {
    XCTAssertEqual(AlarmStopRetryBanner.title, "알람을 멈추지 못했어요.")
    XCTAssertEqual(AlarmStopRetryBanner.message, "루틴은 계속할 수 있어요. 알람만 다시 꺼 볼게요.")
    XCTAssertEqual(AlarmStopRetryBanner.retryTitle, "다시 시도")
  }

  func testEscapeStatesRenderDeterministicallyAtReferenceVariants() async throws {
    let environment = ProcessInfo.processInfo.environment
    let outputDirectory = URL(
      fileURLWithPath: environment["MORU_CAPTURE_OUTPUT_DIR"]
        ?? "/private/tmp/moru-player-escape"
    )

    for state in CaptureState.allCases {
      for variant in MoruVisualCaptureVariant.allCases {
        let first = try MoruVisualCaptureFixture.render(
          try await view(for: state),
          filename: "\(state.rawValue)-\(variant.rawValue).png",
          variant: variant,
          outputDirectory: outputDirectory
        )
        let second = try MoruVisualCaptureFixture.render(
          try await view(for: state),
          filename: "\(state.rawValue)-\(variant.rawValue)-repeat.png",
          variant: variant,
          outputDirectory: outputDirectory
        )

        XCTAssertEqual(first.size, CGSize(width: 393, height: 852), state.rawValue)
        XCTAssertEqual(first.pngData(), second.pngData(), state.rawValue)
      }
    }
  }

  // MARK: - States

  private func view(for state: CaptureState) async throws -> AnyView {
    switch state {
    case .saveFailureBanner:
      let viewModel = makeViewModel(finalizer: EscapeFailingFinalizer())
      viewModel.resolveRoutine()
      viewModel.completeCurrentStep(transcript: "완료했어요")
      viewModel.finishStepCompletedScreen()
      viewModel.completeCurrentStep()
      viewModel.finishStepCompletedScreen()
      XCTAssertNotNil(viewModel.errorMessage)
      return AnyView(RoutinePlayerView(viewModel: viewModel))

    case .discardDialog:
      let viewModel = makeViewModel(finalizer: EscapeFailingFinalizer())
      viewModel.resolveRoutine()
      viewModel.requestCloseRoutine()
      viewModel.confirmActiveDialog()
      viewModel.requestDiscardUnsavedRun()
      XCTAssertEqual(viewModel.dialogState, .discardUnsavedRun)
      return AnyView(RoutinePlayerView(viewModel: viewModel))

    case .closeDialog:
      let viewModel = makeViewModel()
      viewModel.resolveRoutine()
      viewModel.requestCloseRoutine()
      XCTAssertEqual(viewModel.dialogState, .exit(.userDismissed))
      return AnyView(RoutinePlayerView(viewModel: viewModel))

    case .transcriberUnavailableComplete:
      return try await failedSpeechView(.transcriberUnavailable)

    case .microphoneDeniedComplete:
      return try await failedSpeechView(.microphonePermissionDenied)

    case .alarmStopRetryBanner:
      let viewModel = makeViewModel()
      viewModel.resolveRoutine()
      // AppRouter가 fullScreenCover 콘텐츠에 쓰는 것과 같은 구성
      return AnyView(
        AlarmStopRetryBannerContainer(
          isVisible: true,
          isRetrying: false,
          onRetry: {}
        ) {
          RoutinePlayerView(viewModel: viewModel)
        }
      )
    }
  }

  private func failedSpeechView(
    _ error: AppleSpeechRecognitionSessionError
  ) async throws -> AnyView {
    let viewModel = makeViewModel()
    viewModel.resolveRoutine()

    let controller = SpeechInputController(
      makeSession: { EscapeFailingSpeechSession(startError: error) }
    )
    await controller.start()
    XCTAssertNotNil(controller.permanentFailure)

    return AnyView(
      RoutinePlayerView(
        viewModel: viewModel,
        speechInputController: controller
      )
    )
  }

  private func makeViewModel(
    finalizer: any RegularRoutineFinalizing = EscapeSucceedingFinalizer()
  ) -> RoutinePlayerViewModel {
    let routine = escapeRoutine
    let guidanceCoordinator = RoutineGuidanceCoordinator(
      player: NoopRoutineGuidancePlayer(),
      playbackState: RoutineGuidancePlaybackState()
    )

    return RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(
        routineID: routine.id,
        source: .manual
      ),
      resolver: EscapeResolver(routine: routine),
      finalizer: finalizer,
      guidanceCoordinator: guidanceCoordinator,
      presentationToken: UUID(),
      onEvent: { _, _ in }
    )
  }

  private var escapeRoutine: Routine {
    Routine(
      id: UUID(uuidString: "84000000-0000-0000-0000-000000000001")!,
      name: "탈출구 루틴",
      steps: [
        RoutineStep(
          id: UUID(uuidString: "84000000-0000-0000-0000-000000000011")!,
          presetItemID: "ENERGY-01",
          type: .confirm,
          title: "잠자리 정리하기",
          order: 0,
          estimatedSeconds: 60
        ),
        RoutineStep(
          id: UUID(uuidString: "84000000-0000-0000-0000-000000000012")!,
          type: .timer,
          title: "가볍게 스트레칭하기",
          order: 1,
          estimatedSeconds: 180
        ),
      ]
    )
  }
}

@MainActor
private final class EscapeResolver: ResolveRoutineExecutionUseCaseProtocol {
  private let routine: Routine

  init(routine: Routine) {
    self.routine = routine
  }

  func execute(_ request: ResolveRoutineExecutionRequest) -> RoutineExecutionResolution {
    .available(routine)
  }
}

private enum EscapeTestError: Error {
  case saveFailed
}

@MainActor
private final class EscapeFailingFinalizer: RegularRoutineFinalizing {
  func finalize(_ request: SaveRoutineRunRequest) throws -> RoutineCompletionSummary {
    throw EscapeTestError.saveFailed
  }
}

@MainActor
private final class EscapeSucceedingFinalizer: RegularRoutineFinalizing {
  func finalize(_ request: SaveRoutineRunRequest) throws -> RoutineCompletionSummary {
    try makeRoutineCompletionSummary(
      routine: request.routine,
      persistedRunID: UUID(uuidString: "84000000-0000-0000-0000-000000000021"),
      startedAt: request.startedAt,
      completedAt: request.completedAt,
      results: request.results,
      endedEarly: request.endedEarly
    ).get()
  }
}

@MainActor
private final class EscapeFailingSpeechSession: SpeechInputSession {
  var eventHandler: ((SpeechInputSessionEvent) -> Void)?
  private let startError: AppleSpeechRecognitionSessionError

  init(startError: AppleSpeechRecognitionSessionError) {
    self.startError = startError
  }

  func start() async throws {
    throw startError
  }

  func finish() async throws -> String {
    ""
  }

  func cancel() {}
}
