//
//  BundledRoutineAudioTests.swift
//  MoruTests
//

import Foundation
import XCTest
@testable import Moru

@MainActor
final class BundledRoutineAudioTests: XCTestCase {
  func testVoiceCatalogueUsesFourBundledVoicesAndAoedeFallback() {
    XCTAssertEqual(
      VoiceProfile.localVoices.map(\.id),
      [
        "moru.bundle.aoede",
        "moru.bundle.charon",
        "moru.bundle.kore",
        "moru.bundle.orus",
      ]
    )
    XCTAssertEqual(
      VoiceProfile.localVoices.map(\.displayName),
      ["민서", "현우", "지유", "은우"]
    )
    XCTAssertEqual(
      VoiceProfile.localVoices.map(\.assetVoiceCode),
      ["Aoede", "Charon", "Kore", "Orus"]
    )

    for legacyID in ["Yuna", "Sora", "moru-local", "moru.ko.yuna", "moru.ko.sora"] {
      XCTAssertEqual(VoiceProfile.fallback(id: legacyID), .aoede)
    }
  }

  func testEveryBundledVoiceHasTheCommonPreviewCue() {
    let loader = RoutineAudioResourceLoader()
    let probe = BundledVoiceAvailabilityProbe(resourceLoader: loader)

    XCTAssertTrue(VoiceProfile.localVoices.allSatisfy(probe.isAvailable))
  }

  func testPreviewUsesCommonEnergyIntroAndStopInvalidatesPendingPlayback() async {
    let state = RoutineGuidancePlaybackState()
    let player = RoutineGuidancePlayerSpy(playbackState: state)
    let preview = BundledVoicePreviewPlayer(
      availabilityProbe: AvailableVoiceProbe(),
      guidancePlayer: player
    )

    XCTAssertTrue(preview.previewVoice(.kore))
    await drainTasks()

    XCTAssertEqual(
      player.cues,
      [
        GuidanceCueCall(
          itemID: BundledVoiceAvailabilityProbe.previewItemID,
          voiceCode: VoiceProfile.kore.assetVoiceCode,
          kind: .intro
        ),
      ]
    )

    preview.stopVoicePreview()

    XCTAssertGreaterThanOrEqual(player.stopCallCount, 1)
    XCTAssertFalse(state.isPlaying)
  }

  func testGuidanceCoordinatorPlaysIntroHalfwayReminderAndDoneOnce() async {
    let state = RoutineGuidancePlaybackState()
    let player = RoutineGuidancePlayerSpy(playbackState: state)
    let delay = ImmediateGuidanceDelay()
    let coordinator = RoutineGuidanceCoordinator(
      player: player,
      playbackState: state,
      voiceCode: VoiceProfile.charon.assetVoiceCode,
      delay: delay
    )
    let step = RoutineStep(
      presetItemID: "ENERGY-02",
      type: .timer,
      title: "물 마시기",
      order: 0,
      estimatedSeconds: 60
    )

    coordinator.stepDidStart(step)
    await drainTasks()

    XCTAssertEqual(delay.delays, [.seconds(30)])
    XCTAssertEqual(player.cues.filter { $0.kind == .intro }.count, 1)
    XCTAssertEqual(player.cues.filter { $0.kind == .remind }.count, 1)
    XCTAssertTrue(
      player.cues.allSatisfy {
        $0.itemID == "ENERGY-02"
          && $0.voiceCode == VoiceProfile.charon.assetVoiceCode
      }
    )

    coordinator.stepDidComplete(step)
    await drainTasks()

    XCTAssertEqual(player.cues.filter { $0.kind == .done }.count, 1)
  }

  func testFastStepTransitionCancelsReminderAndMissingPresetStaysSilent() async {
    let state = RoutineGuidancePlaybackState()
    let player = RoutineGuidancePlayerSpy(playbackState: state)
    let coordinator = RoutineGuidanceCoordinator(
      player: player,
      playbackState: state,
      delay: SleepingGuidanceDelay()
    )
    let presetStep = RoutineStep(
      presetItemID: "ENERGY-02",
      type: .timer,
      title: "물 마시기",
      order: 0,
      estimatedSeconds: 60
    )
    let customStep = RoutineStep(
      type: .confirm,
      title: "직접 만든 단계",
      order: 1,
      estimatedSeconds: 60
    )

    coordinator.stepDidStart(presetStep)
    await drainTasks()
    coordinator.stepDidComplete(presetStep)
    coordinator.stepDidStart(customStep)
    await drainTasks()

    XCTAssertEqual(player.cues.filter { $0.kind == .intro }.count, 1)
    XCTAssertEqual(player.cues.filter { $0.kind == .remind }.count, 0)
    XCTAssertEqual(player.cues.filter { $0.kind == .done }.count, 0)
    XCTAssertFalse(state.isPlaying)
  }

  func testCorruptCueIsANoopAndDoesNotExposePlayingState() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let audioURL = directory.appendingPathComponent("corrupt.mp3")
    try Data("not an audio file".utf8).write(to: audioURL)
    let mapping = """
    항목ID,항목명,목표,유형,멘트종류,보이스,파일경로,보이스코드
    TEST-01,테스트,활력,확인형,intro,민서,corrupt.mp3,Aoede
    """
    try mapping.write(
      to: directory.appendingPathComponent("routine-audio-mapping.csv"),
      atomically: true,
      encoding: .utf8
    )
    let state = RoutineGuidancePlaybackState()
    let player = BundledRoutineGuidancePlayer(
      resourceLoader: RoutineAudioResourceLoader(resourceDirectory: directory),
      playbackState: state
    )

    let result = await player.play(
      itemID: "TEST-01",
      voiceCode: "Aoede",
      kind: .intro
    )

    XCTAssertFalse(state.isPlaying)
    XCTAssertEqual(result, .cancelled)
  }

  func testRoutinePlayerTransitionsDriveCueLifecycleWithoutDuplicates() async {
    let state = RoutineGuidancePlaybackState()
    let player = RoutineGuidancePlayerSpy(playbackState: state)
    let coordinator = RoutineGuidanceCoordinator(
      player: player,
      playbackState: state,
      delay: SleepingGuidanceDelay()
    )
    let firstStep = RoutineStep(
      presetItemID: "ENERGY-02",
      type: .confirm,
      title: "물 마시기",
      order: 0,
      estimatedSeconds: 60
    )
    let secondStep = RoutineStep(
      presetItemID: "HEALTH-01",
      type: .timer,
      title: "스트레칭",
      order: 1,
      estimatedSeconds: 60
    )
    let routine = Routine(name: "음성 루틴", steps: [firstStep, secondStep])
    let viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: GuidanceRoutineResolver(routine: routine),
      finalizer: GuidanceTrialFinalizer(),
      guidanceCoordinator: coordinator,
      presentationToken: UUID(),
      onEvent: { _, _ in }
    )

    viewModel.resolveRoutine()
    viewModel.resolveRoutine()
    await drainTasks()
    viewModel.completeCurrentStep()
    await drainTasks()
    viewModel.finishStepCompletedScreen()
    await drainTasks()
    viewModel.requestSkipStep()
    viewModel.confirmActiveDialog()
    await drainTasks()

    XCTAssertEqual(player.cues.filter { $0.kind == .intro }.count, 2)
    XCTAssertEqual(player.cues.filter { $0.kind == .done }.count, 1)
    XCTAssertEqual(player.cues.filter { $0.kind == .remind }.count, 0)
    XCTAssertFalse(state.isPlaying)

    guard case .summary = viewModel.screenState else {
      XCTFail("Skipping the last step should finish the trial.")
      return
    }
  }

  func testCompletedScreenWaitsForDoneCueBeforeStartingNextStep() async {
    let state = RoutineGuidancePlaybackState()
    let player = RoutineGuidancePlayerSpy(playbackState: state)
    let coordinator = RoutineGuidanceCoordinator(
      player: player,
      playbackState: state,
      delay: SleepingGuidanceDelay()
    )
    let firstStep = RoutineStep(
      presetItemID: "ENERGY-02",
      type: .confirm,
      title: "물 마시기",
      order: 0
    )
    let secondStep = RoutineStep(
      presetItemID: "HEALTH-01",
      type: .timer,
      title: "스트레칭",
      order: 1
    )
    let routine = Routine(name: "음성 루틴", steps: [firstStep, secondStep])
    let viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: GuidanceRoutineResolver(routine: routine),
      finalizer: GuidanceTrialFinalizer(),
      guidanceCoordinator: coordinator,
      presentationToken: UUID(),
      onEvent: { _, _ in }
    )

    viewModel.resolveRoutine()
    await drainTasks()
    viewModel.completeCurrentStep()
    await drainTasks()

    let transitionTask = Task { @MainActor in
      await viewModel.finishStepCompletedScreenAfterGuidance()
    }
    await drainTasks()

    guard case .stepCompleted(let completedStep) = viewModel.screenState else {
      XCTFail("The completion screen must remain visible during the done cue.")
      return
    }
    XCTAssertEqual(completedStep.id, firstStep.id)

    player.finishPlayback()
    await transitionTask.value
    await drainTasks()

    guard case .running(let runningStep) = viewModel.screenState else {
      XCTFail("The next step must start after the done cue finishes.")
      return
    }
    XCTAssertEqual(runningStep.id, secondStep.id)
  }

  func testSpeechStartBarrierWaitsForIntroCompletion() async {
    let state = RoutineGuidancePlaybackState()
    let player = RoutineGuidancePlayerSpy(playbackState: state)
    let coordinator = RoutineGuidanceCoordinator(
      player: player,
      playbackState: state,
      delay: SleepingGuidanceDelay()
    )
    let step = RoutineStep(
      presetItemID: "ENERGY-02",
      type: .confirm,
      title: "물 마시기",
      order: 0
    )
    let routine = Routine(name: "음성 루틴", steps: [step])
    let viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: GuidanceRoutineResolver(routine: routine),
      finalizer: GuidanceTrialFinalizer(),
      guidanceCoordinator: coordinator,
      presentationToken: UUID(),
      onEvent: { _, _ in }
    )

    viewModel.resolveRoutine()
    let barrierTask = Task { @MainActor in
      await viewModel.waitUntilIntroFinishes(for: step.id)
    }
    await drainTasks()

    XCTAssertFalse(barrierTask.isCancelled)
    XCTAssertTrue(state.isPlaying)

    player.finishPlayback()
    let didFinish = await barrierTask.value

    XCTAssertTrue(didFinish)
  }

  func testInterruptedIntroEndsWaitAndKeepsCurrentStep() async {
    let state = RoutineGuidancePlaybackState()
    let player = RoutineGuidancePlayerSpy(playbackState: state)
    let coordinator = RoutineGuidanceCoordinator(
      player: player,
      playbackState: state,
      delay: SleepingGuidanceDelay()
    )
    let step = RoutineStep(
      presetItemID: "ENERGY-02",
      type: .input,
      title: "오늘의 다짐",
      order: 0
    )
    let routine = Routine(name: "음성 루틴", steps: [step])
    let viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: GuidanceRoutineResolver(routine: routine),
      finalizer: GuidanceTrialFinalizer(),
      guidanceCoordinator: coordinator,
      presentationToken: UUID(),
      onEvent: { _, _ in }
    )

    viewModel.resolveRoutine()
    let barrierTask = Task { @MainActor in
      await viewModel.waitUntilIntroFinishes(for: step.id)
    }
    await drainTasks()
    viewModel.runtimeDidInterrupt()

    let didFinish = await barrierTask.value
    XCTAssertFalse(didFinish)
    XCTAssertFalse(state.isPlaying)
    guard case .running(let currentStep) = viewModel.screenState else {
      XCTFail("An interruption must keep the current step running.")
      return
    }
    XCTAssertEqual(currentStep.id, step.id)
  }

  func testSpeechAudioSessionStopsGuidanceBeforeActivationAttempt() async {
    let state = RoutineGuidancePlaybackState()
    let player = RoutineGuidancePlayerSpy(playbackState: state)
    let coordinator = RoutineAudioSessionCoordinator(guidancePlayback: player)

    do {
      try await coordinator.activateForSpeechInput()
    } catch {
      // A simulator without an input route can reject audio-session activation.
    }
    coordinator.deactivateSpeechInput()
    coordinator.deactivateSpeechInput()
    let playbackTask = Task { @MainActor in
      await player.play(
        itemID: "ENERGY-02",
        voiceCode: VoiceProfile.aoede.assetVoiceCode,
        kind: .done
      )
    }
    await drainTasks()

    XCTAssertEqual(player.stopAndWaitCallCount, 1)
    XCTAssertEqual(player.resumeCallCount, 1)
    XCTAssertEqual(player.cues.count, 1)
    XCTAssertTrue(state.isPlaying)

    player.finishPlayback()
    let result = await playbackTask.value
    XCTAssertEqual(result, .completed)
  }

  private func drainTasks() async {
    for _ in 0..<10 {
      await Task.yield()
    }
  }
}

private struct GuidanceCueCall: Equatable {
  let itemID: String
  let voiceCode: String
  let kind: RoutineAudioCueKind
}

@MainActor
private final class RoutineGuidancePlayerSpy: RoutineGuidancePlaying {
  private let playbackState: RoutineGuidancePlaybackState
  private(set) var cues: [GuidanceCueCall] = []
  private(set) var stopCallCount = 0
  private(set) var stopAndWaitCallCount = 0
  private(set) var resumeCallCount = 0
  private var isSuspendedForSpeechInput = false
  private var playbackContinuation: CheckedContinuation<GuidancePlaybackResult, Never>?

  init(playbackState: RoutineGuidancePlaybackState) {
    self.playbackState = playbackState
  }

  func play(
    itemID: String,
    voiceCode: String,
    kind: RoutineAudioCueKind
  ) async -> GuidancePlaybackResult {
    guard !isSuspendedForSpeechInput else {
      return .cancelled
    }

    finishPlayback(with: .cancelled)
    cues.append(GuidanceCueCall(itemID: itemID, voiceCode: voiceCode, kind: kind))
    playbackState.update(isPlaying: true)
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        playbackContinuation = continuation
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.finishPlayback(with: .cancelled)
      }
    }
  }

  func stop() {
    stopCallCount += 1
    finishPlayback(with: .cancelled)
  }

  func stopAndWaitUntilIdle() async {
    stopAndWaitCallCount += 1
    isSuspendedForSpeechInput = true
    stop()
  }

  func resumeAfterSpeechInput() {
    resumeCallCount += 1
    isSuspendedForSpeechInput = false
  }

  func finishPlayback() {
    finishPlayback(with: .completed)
  }

  private func finishPlayback(with result: GuidancePlaybackResult) {
    playbackState.update(isPlaying: false)
    let continuation = playbackContinuation
    playbackContinuation = nil
    continuation?.resume(returning: result)
  }
}

private struct AvailableVoiceProbe: VoiceAvailabilityProbing {
  func isAvailable(_ voice: VoiceProfile) -> Bool {
    VoiceProfile.localVoices.contains(voice)
  }
}

@MainActor
private final class ImmediateGuidanceDelay: RoutineGuidanceDelaying {
  private(set) var delays: [Duration] = []

  func wait(for delay: Duration) async throws {
    delays.append(delay)
  }
}

private struct SleepingGuidanceDelay: RoutineGuidanceDelaying {
  func wait(for delay: Duration) async throws {
    try await Task.sleep(for: .seconds(60))
  }
}

@MainActor
private final class GuidanceRoutineResolver: ResolveRoutineExecutionUseCaseProtocol {
  private let routine: Routine

  init(routine: Routine) {
    self.routine = routine
  }

  func execute(_ request: ResolveRoutineExecutionRequest) -> RoutineExecutionResolution {
    .available(routine)
  }
}

@MainActor
private final class GuidanceTrialFinalizer: TrialRoutineFinalizing {
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
