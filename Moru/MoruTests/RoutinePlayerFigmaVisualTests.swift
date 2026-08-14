//
//  RoutinePlayerFigmaVisualTests.swift
//  MoruTests
//
//  Created by Codex on 7/24/26.
//

import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Moru

@MainActor
final class RoutinePlayerFigmaVisualTests: XCTestCase {
  func testRoutinePlayerCopyUsesPresetSpecificAndTruthfulFallbackText() {
    let bedAliases = ["ENERGY-01", "HEALTH-02", "CALM-01", "HABIT-01"]
    for presetItemID in bedAliases {
      let bedStep = step(
        index: 1,
        presetItemID: presetItemID,
        type: .confirm,
        title: "잠자리 정리하기",
        instruction: "이 문구보다 preset copy가 우선이에요.",
        seconds: 60
      )
      XCTAssertEqual(
        RoutinePlayerCopy.guide(for: bedStep),
        "이불 정리가 끝났나요? 완료됐으면\n말해주세요."
      )
    }

    let customStep = step(
      index: 2,
      type: .confirm,
      title: "사용자 항목",
      instruction: "사용자가 저장한 안내를 그대로 보여줘요.",
      seconds: 60
    )
    XCTAssertEqual(
      RoutinePlayerCopy.guide(for: customStep),
      "사용자가 저장한 안내를 그대로 보여줘요."
    )

    let stretchingStep = step(
      index: 3,
      presetItemID: "ENERGY-10",
      type: .timer,
      title: "가볍게 스트레칭하기",
      seconds: 180
    )
    XCTAssertEqual(
      RoutinePlayerCopy.timerSegments(for: stretchingStep)?.map(\.title),
      ["가볍게 스트레칭하기"]
    )
    XCTAssertEqual(
      RoutinePlayerCopy.timerSegments(for: stretchingStep)?.map {
        $0.durationSeconds ?? 0
      },
      [180]
    )

    let editedTimerStep = step(
      index: 4,
      presetItemID: "ENERGY-10",
      type: .timer,
      title: "내가 만든 집중 타이머",
      instruction: "책상 위 한 구역만 정리해요.",
      seconds: 90
    )
    XCTAssertEqual(
      RoutinePlayerCopy.timerSegments(for: editedTimerStep),
      [
        RoutinePlayerCopy.TimerSegment(
          title: "책상 위 한 구역만 정리해요.",
          duration: "1분 30초",
          durationSeconds: 90
        ),
      ]
    )
    XCTAssertEqual(
      RoutinePlayerCopy.guide(for: editedTimerStep),
      "책상 위 한 구역만 정리해요."
    )
  }

  func testRoutinePlayerStatesRenderDeterministicallyAtReferenceVariants() async throws {
    let environment = ProcessInfo.processInfo.environment
    let phase = environment["MORU_ROUTINE_PLAYER_CAPTURE_PHASE"] ?? "after"
    let outputDirectory = URL(
      fileURLWithPath: environment["MORU_CAPTURE_OUTPUT_DIR"]
        ?? "/private/tmp/moru-figma-p4-\(phase)"
    )

    for state in RoutinePlayerCaptureState.allCases {
      for variant in MoruVisualCaptureVariant.allCases {
        let filename = "\(state.rawValue)-\(variant.rawValue).png"
        let first = try MoruVisualCaptureFixture.render(
          try await view(for: state),
          filename: filename,
          variant: variant,
          outputDirectory: outputDirectory
        )
        let second = try MoruVisualCaptureFixture.render(
          try await view(for: state),
          filename: "\(state.rawValue)-\(variant.rawValue)-repeat.png",
          variant: variant,
          outputDirectory: outputDirectory
        )

        XCTAssertEqual(first.size, CGSize(width: 393, height: 852))
        XCTAssertEqual(first.scale, 3)
        XCTAssertEqual(first.pngData(), second.pngData())
        try assertMatchesApprovedBaseline(
          first,
          state: state,
          variant: variant
        )
      }
    }
  }

  private func assertMatchesApprovedBaseline(
    _ image: UIImage,
    state: RoutinePlayerCaptureState,
    variant: MoruVisualCaptureVariant,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let baselineURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(
        "docs/figma-pilot-review-bundle/P4-routine-player-completion/states"
      )
      .appendingPathComponent("\(state.rawValue)-\(variant.rawValue)")
      .appendingPathComponent("after.png")
    let baseline = try XCTUnwrap(
      UIImage(contentsOfFile: baselineURL.path),
      "Missing approved visual baseline: \(baselineURL.path)",
      file: file,
      line: line
    )
    let actualHash = try visualHash(for: image)
    let baselineHash = try visualHash(for: baseline)
    let distance = zip(actualHash, baselineHash).reduce(0) { result, pair in
      result + Int((pair.0 ^ pair.1).nonzeroBitCount)
    }

    XCTAssertLessThanOrEqual(
      distance,
      24,
      "Visual regression in \(state.rawValue)-\(variant.rawValue), "
        + "hash distance: \(distance)",
      file: file,
      line: line
    )
  }

  private func visualHash(for image: UIImage) throws -> Data {
    let width = 17
    let height = 32
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try XCTUnwrap(
      CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )
    let cgImage = try XCTUnwrap(image.cgImage)
    context.interpolationQuality = .high
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var luminance = [Int]()
    luminance.reserveCapacity(width * height)
    for offset in stride(from: 0, to: pixels.count, by: 4) {
      let red = 299 * Int(pixels[offset])
      let green = 587 * Int(pixels[offset + 1])
      let blue = 114 * Int(pixels[offset + 2])
      luminance.append((red + green + blue) / 1_000)
    }

    var hash = Data(capacity: (width - 1) * height / 8)
    var byte: UInt8 = 0
    var bitIndex = 0
    for row in 0..<height {
      for column in 0..<(width - 1) {
        if luminance[row * width + column] > luminance[row * width + column + 1] {
          byte |= 1 << (7 - bitIndex)
        }
        bitIndex += 1
        if bitIndex == 8 {
          hash.append(byte)
          byte = 0
          bitIndex = 0
        }
      }
    }
    return hash
  }

  private func view(
    for state: RoutinePlayerCaptureState
  ) async throws -> AnyView {
    switch state {
    case .regularConfirm:
      return try await runningView(
        currentStepIndex: 0,
        isGuidancePlaying: true,
        keepsGuidanceActive: true
      )
    case .confirmTranscript:
      return try await runningView(
        currentStepIndex: 0,
        transcript: "네, 끝났어요.",
        waveformLevels: captureWaveformLevels
      )
    case .regularTimer:
      return try await runningView(
        currentStepIndex: 1,
        isGuidancePlaying: true,
        timerRemainingSeconds: 108
      )
    case .regularStructuredTimer:
      return try await runningView(
        currentStepIndex: 3,
        isGuidancePlaying: true,
        timerRemainingSeconds: 108,
        activeTimerSegmentIndex: 3
      )
    case .regularInput:
      return try await runningView(
        currentStepIndex: 2,
        isGuidancePlaying: true,
        keepsGuidanceActive: true
      )
    case .inputLongKorean:
      return try await runningView(
        currentStepIndex: 2,
        transcript: """
        오늘도 최선을 다해서 행복한 하루를 만들고 싶습니다. 오늘은 할 일을 \
        미루지 않겠습니다. 휴대폰 보느라 늦잠도 자지 않고, 아침에 빨리 \
        일어나겠습니다.
        """,
        waveformLevels: captureWaveformLevels
      )
    case .stepCompleted:
      let viewModel = makeViewModel()
      viewModel.resolveRoutine()
      viewModel.completeCurrentStep(transcript: "완료했어요")
      return AnyView(RoutinePlayerView(viewModel: viewModel))
    case .skipDialog:
      let viewModel = makeViewModel()
      advance(viewModel, to: 3)
      viewModel.requestSkipStep()
      return AnyView(RoutinePlayerView(viewModel: viewModel))
    case .endDialog:
      let viewModel = makeViewModel()
      advance(viewModel, to: 3)
      viewModel.requestEndRoutine()
      return AnyView(RoutinePlayerView(viewModel: viewModel))
    case .resolutionRetry:
      let viewModel = makeViewModel(
        resolution: .temporarilyUnavailable(.repositoryUnavailable)
      )
      viewModel.resolveRoutine()
      return AnyView(RoutinePlayerView(viewModel: viewModel))
    case .terminalFailure:
      let viewModel = makeViewModel(resolution: .notFound)
      viewModel.resolveRoutine()
      return AnyView(RoutinePlayerView(viewModel: viewModel))
    case .trialConfirm:
      return try await runningView(currentStepIndex: 8, isTrial: true)
    }
  }

  private func runningView(
    currentStepIndex: Int,
    isTrial: Bool = false,
    transcript: String? = nil,
    waveformLevels: [Float]? = nil,
    isGuidancePlaying: Bool = false,
    keepsGuidanceActive: Bool = false,
    timerRemainingSeconds: Int? = nil,
    activeTimerSegmentIndex: Int? = nil
  ) async throws -> AnyView {
    let viewModel = makeViewModel(
      isTrial: isTrial,
      isGuidancePlaying: isGuidancePlaying,
      keepsGuidanceActive: keepsGuidanceActive
    )
    advance(viewModel, to: currentStepIndex)

    let session = RoutinePlayerCaptureSpeechSession()
    let speechInputController = SpeechInputController(
      silenceTimeout: 60,
      makeSession: { session }
    )
    if viewModel.currentStepIsVoiceDriven, !keepsGuidanceActive {
      await speechInputController.start()
      if let waveformLevels {
        session.send(.audioLevels(waveformLevels))
      }
      if let transcript {
        session.send(.transcript(transcript, isFinal: false))
      }
    }

    return AnyView(
      RoutinePlayerView(
        viewModel: viewModel,
        speechInputController: speechInputController
      )
      .environment(
        \.routinePlayerCaptureTimerRemainingSeconds,
        timerRemainingSeconds
      )
      .environment(
        \.routinePlayerCaptureActiveTimerSegmentIndex,
        activeTimerSegmentIndex
      )
    )
  }

  private func advance(
    _ viewModel: RoutinePlayerViewModel,
    to targetIndex: Int
  ) {
    viewModel.resolveRoutine()

    guard targetIndex > 0 else {
      return
    }

    for _ in 0..<targetIndex {
      viewModel.completeCurrentStep(
        inputText: "오늘도 차분하게 시작할게요.",
        transcript: "완료했어요"
      )
      viewModel.finishStepCompletedScreen()
    }
  }

  private func makeViewModel(
    isTrial: Bool = false,
    isGuidancePlaying: Bool = false,
    keepsGuidanceActive: Bool = false,
    resolution: RoutineExecutionResolution? = nil
  ) -> RoutinePlayerViewModel {
    let routine = isTrial ? trialCaptureRoutine : captureRoutine
    let resolver = RoutinePlayerCaptureResolver(
      resolution: resolution ?? .available(routine)
    )
    let playbackState = RoutineGuidancePlaybackState()
    playbackState.update(isPlaying: isGuidancePlaying)
    let guidancePlayer: any RoutineGuidancePlaying = keepsGuidanceActive
      ? RoutinePlayerCaptureGuidancePlayer()
      : NoopRoutineGuidancePlayer()
    let guidanceCoordinator = RoutineGuidanceCoordinator(
      player: guidancePlayer,
      playbackState: playbackState
    )

    if isTrial {
      return RoutinePlayerViewModel(
        request: TrialRoutineExecutionRequest(routineID: routine.id),
        resolver: resolver,
        finalizer: RoutinePlayerCaptureTrialFinalizer(),
        guidanceCoordinator: guidanceCoordinator,
        presentationToken: UUID(),
        onEvent: { _, _ in }
      )
    }

    return RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(
        routineID: routine.id,
        source: .manual
      ),
      resolver: resolver,
      finalizer: RoutinePlayerCaptureRegularFinalizer(),
      guidanceCoordinator: guidanceCoordinator,
      presentationToken: UUID(),
      onEvent: { _, _ in }
    )
  }

  private var captureRoutine: Routine {
    Routine(
      id: UUID(uuidString: "81000000-0000-0000-0000-000000000001")!,
      name: "활력 루틴",
      steps: [
        step(
          index: 1,
          presetItemID: "ENERGY-01",
          type: .confirm,
          title: "잠자리 정리하기",
          instruction: "이불과 베개를 정리해 주세요.",
          seconds: 60
        ),
        step(
          index: 2,
          presetItemID: "CALM-07",
          type: .timer,
          title: "심호흡하며 명상하기",
          instruction: "눈을 감고 천천히 호흡해봐요.",
          seconds: 180
        ),
        step(
          index: 3,
          presetItemID: "ENERGY-16",
          type: .input,
          title: "오늘의 다짐 확언하기",
          instruction: "",
          seconds: 60
        ),
        step(
          index: 4,
          presetItemID: "ENERGY-10",
          type: .timer,
          title: "가볍게 스트레칭하기",
          instruction: "목과 어깨를 천천히 풀어봐요.",
          seconds: 180
        ),
        step(index: 5, type: .timer, title: "짧은 독서 몰입하기", seconds: 300),
        step(index: 6, type: .input, title: "감정과 생각을 기록하기", seconds: 120),
        step(index: 7, type: .confirm, title: "물 한 잔 마시기", seconds: 60),
        step(index: 8, type: .timer, title: "창문 열고 환기하기", seconds: 60),
        step(index: 9, type: .confirm, title: "오늘 계획 확인하기", seconds: 60),
      ],
      isActive: true,
      createdAt: Date(timeIntervalSince1970: 1_784_841_300),
      updatedAt: Date(timeIntervalSince1970: 1_784_841_300)
    )
  }

  private var trialCaptureRoutine: Routine {
    var routine = captureRoutine
    guard let firstStep = routine.steps.first else {
      return routine
    }

    var steps = Array(routine.steps.dropFirst()) + [firstStep]
    for index in steps.indices {
      steps[index].order = index
    }
    routine.steps = steps
    return routine
  }

  private var captureWaveformLevels: [Float] {
    [
      0.18, 0.34, 0.62, 0.84, 0.48,
      0.26, 0.54, 0.78, 0.44, 0.22,
      0.40, 0.66, 0.88, 0.58, 0.30,
      0.50, 0.74, 0.42, 0.24, 0.16,
    ]
  }

  private func step(
    index: Int,
    presetItemID: String? = nil,
    type: RoutineStepType,
    title: String,
    instruction: String = "",
    seconds: Int
  ) -> RoutineStep {
    RoutineStep(
      id: UUID(
        uuidString: String(
          format: "82000000-0000-0000-0000-%012d",
          index
        )
      )!,
      presetItemID: presetItemID,
      type: type,
      title: title,
      instruction: instruction,
      order: index - 1,
      estimatedSeconds: seconds
    )
  }
}

private enum RoutinePlayerCaptureState: String, CaseIterable {
  case regularConfirm = "regular-confirm"
  case confirmTranscript = "confirm-transcript"
  case regularTimer = "regular-timer"
  case regularStructuredTimer = "regular-structured-timer"
  case regularInput = "regular-input"
  case inputLongKorean = "input-long-korean"
  case stepCompleted = "step-completed"
  case skipDialog = "skip-dialog"
  case endDialog = "end-dialog"
  case resolutionRetry = "resolution-retry"
  case terminalFailure = "terminal-failure"
  case trialConfirm = "trial-confirm"
}

@MainActor
private extension RoutinePlayerViewModel {
  var currentStepIsVoiceDriven: Bool {
    guard case .running(let step) = screenState else {
      return false
    }
    return step.type == .confirm || step.type == .input
  }
}

@MainActor
private final class RoutinePlayerCaptureResolver:
  ResolveRoutineExecutionUseCaseProtocol {
  private let resolution: RoutineExecutionResolution

  init(resolution: RoutineExecutionResolution) {
    self.resolution = resolution
  }

  func execute(
    _ request: ResolveRoutineExecutionRequest
  ) -> RoutineExecutionResolution {
    resolution
  }
}

@MainActor
private final class RoutinePlayerCaptureTrialFinalizer: TrialRoutineFinalizing {
  func finalize(
    routine: Routine,
    startedAt: Date,
    completedAt: Date,
    results: [RoutineStepResult]
  ) -> Result<RoutineCompletionSummary, RoutineCompletionSummaryValidationError> {
    makeRoutineCompletionSummary(
      routine: routine,
      persistedRunID: nil,
      startedAt: startedAt,
      completedAt: completedAt,
      results: results,
      endedEarly: false
    )
  }
}

@MainActor
private final class RoutinePlayerCaptureRegularFinalizer: RegularRoutineFinalizing {
  func finalize(
    _ request: SaveRoutineRunRequest
  ) throws -> RoutineCompletionSummary {
    try makeRoutineCompletionSummary(
      routine: request.routine,
      persistedRunID: UUID(
        uuidString: "83000000-0000-0000-0000-000000000001"
      ),
      startedAt: request.startedAt,
      completedAt: request.completedAt,
      results: request.results,
      endedEarly: request.endedEarly,
      streak: RoutineStreak(
        currentDays: 4,
        bestDays: 7,
        completedWeekdays: [.monday, .tuesday, .wednesday, .thursday]
      )
    ).get()
  }
}

@MainActor
private final class RoutinePlayerCaptureSpeechSession: SpeechInputSession {
  var eventHandler: ((SpeechInputSessionEvent) -> Void)?

  func start() async throws {}

  func finish() async throws -> String {
    ""
  }

  func cancel() {}

  func send(_ event: SpeechInputSessionEvent) {
    eventHandler?(event)
  }
}

@MainActor
private final class RoutinePlayerCaptureGuidancePlayer: RoutineGuidancePlaying {
  func play(
    itemID: String,
    voiceCode: String,
    kind: RoutineAudioCueKind
  ) async -> GuidancePlaybackResult {
    do {
      try await Task.sleep(for: .seconds(3_600))
      return .completed
    } catch {
      return .cancelled
    }
  }

  func stop() {}

  func stopAndWaitUntilIdle() async {}

  func resumeAfterSpeechInput() {}
}
