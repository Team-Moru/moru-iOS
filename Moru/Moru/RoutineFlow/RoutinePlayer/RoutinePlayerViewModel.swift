//
//  RoutinePlayerViewModel.swift
//  Moru
//

import Foundation
import Observation

@MainActor
@Observable
final class RoutinePlayerViewModel {
  enum ScreenState {
    case resolving
    case resolutionRetry(RoutineResolutionRetryReason)
    case terminalFailure(RoutineTerminalReason)
    case running(RoutineStep)
    case stepCompleted(RoutineStep)
    case summary(RoutineCompletionPresentation)
  }

  enum DialogState: Equatable {
    enum Exit: Equatable {
      case endedEarly
      case userDismissed
    }

    case skipStep
    case exit(Exit)
  }

  private enum FinalizationMode {
    case trial(any TrialRoutineFinalizing)
    case regular(any RegularRoutineFinalizing)
  }

  private enum PendingTerminalIntent {
    case natural
    case exit(RoutinePlayerExit)
  }

  private struct PendingSave {
    let request: SaveRoutineRunRequest
    let terminalIntent: PendingTerminalIntent
    let finalizer: any RegularRoutineFinalizing
  }

  private let resolver: any ResolveRoutineExecutionUseCaseProtocol
  private let finalizationMode: FinalizationMode
  private let resolutionRequest: ResolveRoutineExecutionRequest
  private let presentationToken: UUID
  private let onEvent: RoutinePlayerEventHandler
  private let startedAt: Date

  private var routine: Routine?
  private var steps: [RoutineStep] = []
  private var pendingSave: PendingSave?
  private var didEmitRunnableContent = false
  private var didRequestExit = false

  private(set) var currentStepIndex = 0
  private(set) var stepResults: [RoutineStepResult] = []
  private(set) var screenState: ScreenState = .resolving
  private(set) var dialogState: DialogState?
  private(set) var isSavingRun = false
  private(set) var errorMessage: String?

  var isStepInteractionDisabled: Bool {
    dialogState != nil || pendingSave != nil || isSavingRun || didRequestExit
  }
  var isSummaryActionDisabled: Bool {
    didRequestExit
  }

  init(
    request: TrialRoutineExecutionRequest,
    resolver: any ResolveRoutineExecutionUseCaseProtocol,
    finalizer: any TrialRoutineFinalizing,
    presentationToken: UUID,
    onEvent: @escaping RoutinePlayerEventHandler
  ) {
    self.resolver = resolver
    self.finalizationMode = .trial(finalizer)
    self.resolutionRequest = ResolveRoutineExecutionRequest(
      routineID: request.routineID,
      launch: .trial
    )
    self.presentationToken = presentationToken
    self.onEvent = onEvent
    self.startedAt = Date()
  }

  init(
    request: RegularRoutineExecutionRequest,
    resolver: any ResolveRoutineExecutionUseCaseProtocol,
    finalizer: any RegularRoutineFinalizing,
    presentationToken: UUID,
    onEvent: @escaping RoutinePlayerEventHandler
  ) {
    let launch: ResolveRoutineExecutionRequest.Launch

    switch request.source {
    case .manual:
      launch = .manual

    case .scheduled:
      launch = .scheduled
    }

    self.resolver = resolver
    self.finalizationMode = .regular(finalizer)
    self.resolutionRequest = ResolveRoutineExecutionRequest(
      routineID: request.routineID,
      launch: launch
    )
    self.presentationToken = presentationToken
    self.onEvent = onEvent
    self.startedAt = Date()
  }

  var currentStepNumberText: String {
    guard case .running(_) = screenState else {
      return "0/0"
    }

    return "\(currentStepIndex + 1)/\(steps.count)"
  }

  var progressValue: Double {
    guard case .running(_) = screenState else {
      return 0
    }

    return Double(currentStepIndex + 1) / Double(steps.count)
  }

  func resolveRoutine() {
    guard !didRequestExit else {
      return
    }

    guard case .resolving = screenState else {
      return
    }

    switch resolver.execute(resolutionRequest) {
    case .available(let routine):
      self.routine = routine
      steps = routine.steps.sorted { $0.order < $1.order }
      currentStepIndex = 0
      stepResults = []
      didEmitRunnableContent = false

      guard let firstStep = steps.first else {
        displayTerminalFailure(.ineligible(.noExecutableSteps))
        return
      }

      screenState = .running(firstStep)

    case .notFound:
      displayTerminalFailure(.notFound)

    case .ineligible(let reason):
      displayTerminalFailure(.ineligible(reason))

    case .temporarilyUnavailable(let reason):
      screenState = .resolutionRetry(reason)
      emit(.resolutionRetryDisplayed(reason))
    }
  }

  func retryResolution() {
    guard case .resolutionRetry = screenState else {
      return
    }

    screenState = .resolving
    resolveRoutine()
  }

  func continueAfterTerminalFailure() {
    guard case .terminalFailure = screenState else {
      return
    }

    emitExit(.terminalUnavailable)
  }

  func runnableContentDidAppear() {
    guard case .running(_) = screenState else {
      return
    }

    guard !didEmitRunnableContent else {
      return
    }

    didEmitRunnableContent = true
    emit(.runnableContentDidAppear(Date()))
  }

  func requestSkipStep() {
    guard !isStepInteractionDisabled else {
      return
    }

    guard case .running(_) = screenState else {
      return
    }

    dialogState = .skipStep
  }

  func requestEndRoutine() {
    requestExitDialog(.endedEarly)
  }

  func requestCloseRoutine() {
    requestExitDialog(.userDismissed)
  }

  func cancelActiveDialog() {
    dialogState = nil
  }

  func confirmActiveDialog() {
    guard let dialogState else {
      return
    }

    self.dialogState = nil

    switch dialogState {
    case .skipStep:
      skipCurrentStep()

    case .exit(let exit):
      confirmExit(exit)
    }
  }

  func completeCurrentStep(
    inputText: String? = nil,
    transcript: String? = nil
  ) {
    guard !isStepInteractionDisabled else {
      return
    }

    guard case .running(let step) = screenState else {
      return
    }

    guard !stepResults.contains(where: { $0.stepID == step.id }) else {
      return
    }
    guard validateTimerDuration(for: step) else {
      return
    }

    let result = RoutineStepResult(
      stepID: step.id,
      stepTitle: step.title,
      stepType: step.type,
      completedAt: Date(),
      skipped: false,
      inputText: inputText,
      transcript: transcript,
      durationSeconds: step.type == .timer ? step.estimatedSeconds : nil
    )

    stepResults.append(result)
    screenState = .stepCompleted(step)
  }

  func skipCurrentStep() {
    guard !isStepInteractionDisabled else {
      return
    }

    guard case .running(let step) = screenState else {
      return
    }

    guard !stepResults.contains(where: { $0.stepID == step.id }) else {
      return
    }
    guard validateTimerDuration(for: step) else {
      return
    }

    let result = RoutineStepResult(
      stepID: step.id,
      stepTitle: step.title,
      stepType: step.type,
      completedAt: nil,
      skipped: true
    )

    stepResults.append(result)
    moveToNextStep()
  }

  func finishStepCompletedScreen() {
    guard !isStepInteractionDisabled else {
      return
    }

    guard case .stepCompleted = screenState else {
      return
    }

    moveToNextStep()
  }

  func retrySavingRun() {
    guard pendingSave != nil else {
      return
    }

    persistPendingSave()
  }

  func requestSummaryRecord() {
    guard case .summary(.regular(let result)) = screenState else {
      return
    }

    emitExit(.summaryRecord(persistedRunID: result.persistedRunID))
  }

  func requestSummaryHome() {
    guard case .summary = screenState else {
      return
    }

    emitExit(.summaryHome)
  }

  private func requestExitDialog(_ exit: DialogState.Exit) {
    guard !isStepInteractionDisabled else {
      return
    }

    guard case .running(_) = screenState else {
      return
    }

    dialogState = .exit(exit)
  }

  private func confirmExit(_ exit: DialogState.Exit) {
    guard !isStepInteractionDisabled else {
      return
    }

    guard case .running(_) = screenState else {
      return
    }

    guard let routine else {
      displayTerminalFailure(.notFound)
      return
    }

    switch exit {
    case .endedEarly:
      finalizeEarlyExit(.endedEarly, routine: routine)

    case .userDismissed:
      finalizeEarlyExit(.userDismissed, routine: routine)
    }
  }

  private func moveToNextStep() {
    let nextStepIndex = currentStepIndex + 1

    guard steps.indices.contains(nextStepIndex) else {
      finalizeNaturalCompletion()
      return
    }

    currentStepIndex = nextStepIndex
    screenState = .running(steps[nextStepIndex])
  }

  private func finalizeNaturalCompletion() {
    guard let routine else {
      displayTerminalFailure(.notFound)
      return
    }

    switch finalizationMode {
    case .trial(let finalizer):
      switch finalizer.finalize(
        routine: routine,
        startedAt: startedAt,
        completedAt: Date(),
        results: stepResults
      ) {
      case .success(let summary):
        screenState = .summary(.trial(summary))
        emit(.completionDisplayed(summary))

      case .failure(let error):
        displayTerminalFailure(.invalidCompletionSummary(error))
      }

    case .regular(let finalizer):
      beginRegularFinalization(
        routine: routine,
        finalizer: finalizer,
        endedEarly: false,
        terminalIntent: .natural
      )
    }
  }

  private func finalizeEarlyExit(
    _ exit: RoutinePlayerExit,
    routine: Routine
  ) {
    switch finalizationMode {
    case .trial:
      emitExit(exit)

    case .regular(let finalizer):
      beginRegularFinalization(
        routine: routine,
        finalizer: finalizer,
        endedEarly: true,
        terminalIntent: .exit(exit)
      )
    }
  }

  private func beginRegularFinalization(
    routine: Routine,
    finalizer: any RegularRoutineFinalizing,
    endedEarly: Bool,
    terminalIntent: PendingTerminalIntent
  ) {
    guard pendingSave == nil else {
      return
    }

    let request = SaveRoutineRunRequest(
      runID: UUID(),
      routine: routine,
      startedAt: startedAt,
      completedAt: Date(),
      results: stepResults,
      endedEarly: endedEarly
    )

    pendingSave = PendingSave(
      request: request,
      terminalIntent: terminalIntent,
      finalizer: finalizer
    )
    persistPendingSave()
  }

  private func persistPendingSave() {
    guard !isSavingRun else {
      return
    }

    guard let pendingSave else {
      return
    }

    isSavingRun = true
    errorMessage = nil

    do {
      let result = try pendingSave.finalizer.finalize(pendingSave.request)

      self.pendingSave = nil
      isSavingRun = false

      switch pendingSave.terminalIntent {
      case .natural:
        screenState = .summary(.regular(result))
        emit(.completionDisplayed(result.summary))

      case .exit(let exit):
        emitExit(exit)
      }
    } catch let error as RegularRoutineFinalizationError {
      self.pendingSave = nil
      isSavingRun = false

      switch error {
      case .missingPersistedRunID:
        displayTerminalFailure(.missingPersistedRunID)
      }
    } catch let error as RoutineCompletionSummaryValidationError {
      self.pendingSave = nil
      isSavingRun = false
      displayTerminalFailure(.invalidCompletionSummary(error))
    } catch {
      errorMessage = "루틴 실행 기록을 저장하지 못했습니다. 다시 시도해 주세요."
      isSavingRun = false
    }
  }

  private func validateTimerDuration(for step: RoutineStep) -> Bool {
    guard step.type == .timer else {
      return true
    }

    guard let estimatedSeconds = step.estimatedSeconds, estimatedSeconds > 0 else {
      displayTerminalFailure(.ineligible(.invalidTimerDuration))
      return false
    }

    return true
  }
  private func displayTerminalFailure(_ reason: RoutineTerminalReason) {
    screenState = .terminalFailure(reason)
    emit(.terminalFailureDisplayed(reason))
  }

  private func emitExit(_ exit: RoutinePlayerExit) {
    guard !didRequestExit else {
      return
    }

    didRequestExit = true
    emit(.exitRequested(exit))
  }

  private func emit(_ event: RoutinePlayerEvent) {
    onEvent(presentationToken, event)
  }
}
