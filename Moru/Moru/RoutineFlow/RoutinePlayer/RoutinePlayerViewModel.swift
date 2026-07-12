//
//  RoutinePlayerViewModel.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import Foundation
import Observation

@MainActor
@Observable
final class RoutinePlayerViewModel {
    enum ScreenState {
        case running
        case stepCompleted(RoutineStep)
        case finished(RoutineRun)
    }

    private let routine: Routine
    private let saveRoutineRunUseCase: any SaveRoutineRunUseCaseProtocol

    private let startedAt: Date
    private let steps: [RoutineStep]
    private var pendingSaveRequest: SaveRoutineRunRequest?

    var currentStepIndex: Int = 0
    var stepResults: [RoutineStepResult] = []

    var screenState: ScreenState = .running

    var isShowingSkipDialog = false
    var isShowingEndDialog = false
    var isSavingRun = false

    var errorMessage: String?
    var isStepInteractionDisabled: Bool {
        pendingSaveRequest != nil || isSavingRun
    }

    init(
        routine: Routine,
        saveRoutineRunUseCase: any SaveRoutineRunUseCaseProtocol
    ) {
        self.routine = routine
        self.saveRoutineRunUseCase = saveRoutineRunUseCase
        self.startedAt = Date()
        self.steps = routine.steps.sorted { $0.order < $1.order }
    }

    var currentStep: RoutineStep? {
        guard steps.indices.contains(currentStepIndex) else {
            return nil
        }

        return steps[currentStepIndex]
    }

    var currentStepNumberText: String {
        guard !steps.isEmpty else { return "0/0" }
        return "\(currentStepIndex + 1)/\(steps.count)"
    }

    var progressValue: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(currentStepIndex + 1) / Double(steps.count)
    }

    func requestSkipStep() {
        guard !isStepInteractionDisabled else { return }
        isShowingSkipDialog = true
    }

    func requestEndRoutine() {
        guard !isStepInteractionDisabled else { return }
        isShowingEndDialog = true
    }

    func cancelSkipStep() {
        isShowingSkipDialog = false
    }

    func cancelEndRoutine() {
        isShowingEndDialog = false
    }

    func completeCurrentStep(
        inputText: String? = nil,
        transcript: String? = nil
    ) {
        guard !isStepInteractionDisabled else { return }
        guard case .running = screenState else { return }
        guard let step = currentStep else { return }

        // 같은 단계가 중복으로 완료되는 것을 방지합니다.
        guard !stepResults.contains(where: { $0.stepID == step.id }) else {
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
            durationSeconds: step.type == .timer
                ? (step.estimatedSeconds ?? 60)
                : nil
        )

        stepResults.append(result)
        screenState = .stepCompleted(step)
    }

    func skipCurrentStep() {
        isShowingSkipDialog = false

        guard !isStepInteractionDisabled else { return }
        guard case .running = screenState else { return }
        guard let step = currentStep else { return }

        // 같은 단계가 중복으로 기록되는 것을 방지합니다.
        guard !stepResults.contains(where: { $0.stepID == step.id }) else {
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
        guard !isStepInteractionDisabled else { return }
        guard case .stepCompleted = screenState else { return }

        moveToNextStep()
    }

    func endRoutine() {
        isShowingEndDialog = false
        guard !isStepInteractionDisabled else { return }
        saveRun(endedEarly: true)
    }
    
    func retrySavingRun() {
        guard let pendingSaveRequest else { return }
        persistRun(using: pendingSaveRequest)
    }

    private func moveToNextStep() {
        if currentStepIndex + 1 < steps.count {
            currentStepIndex += 1
            screenState = .running
        } else {
            saveRun(endedEarly: false)
        }
    }

    private func saveRun(endedEarly: Bool) {
        let request = SaveRoutineRunRequest(
            routine: routine,
            startedAt: startedAt,
            completedAt: Date(),
            results: stepResults,
            endedEarly: endedEarly
        )

        pendingSaveRequest = request
        persistRun(using: request)
    }

    private func persistRun(using request: SaveRoutineRunRequest) {
        guard !isSavingRun else { return }

        isSavingRun = true
        errorMessage = nil

        do {
            let savedRun = try saveRoutineRunUseCase.execute(request)

            // 저장에 성공한 경우에만 완료 화면으로 이동합니다.
            pendingSaveRequest = nil
            screenState = .finished(savedRun)
        } catch {
            // screenState는 변경하지 않습니다.
            // 따라서 기존 루틴 실행 화면이 그대로 유지됩니다.
            errorMessage = """
            루틴 실행 기록을 저장하지 못했습니다. \
            다시 시도해 주세요.
            """
        }

        isSavingRun = false
    }
}
