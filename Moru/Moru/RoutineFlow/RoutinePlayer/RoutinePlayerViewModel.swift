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
        case finished
    }

    private let routine: Routine
    private let runRepository: RoutineRunRepository?

    private let startedAt: Date
    private let steps: [RoutineStep]

    var currentStepIndex: Int = 0
    var stepResults: [RoutineStepResult] = []

    var screenState: ScreenState = .running

    var isShowingSkipDialog = false
    var isShowingEndDialog = false

    var errorMessage: String?

    init(
        routine: Routine,
        runRepository: RoutineRunRepository? = nil
    ) {
        self.routine = routine
        self.runRepository = runRepository
        self.startedAt = Date()
        self.steps = routine.steps.sorted { $0.order < $1.order }
    }

    var routineName: String {
        routine.name
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

    var completionRate: Int {
        guard !steps.isEmpty else { return 0 }

        let completedCount = stepResults.filter { !$0.skipped }.count
        return Int((Double(completedCount) / Double(steps.count)) * 100)
    }

    var completedStepCount: Int {
        stepResults.filter { !$0.skipped }.count
    }

    var skippedStepCount: Int {
        stepResults.filter { $0.skipped }.count
    }

    func requestSkipStep() {
        isShowingSkipDialog = true
    }

    func requestEndRoutine() {
        isShowingEndDialog = true
    }

    func cancelSkipStep() {
        isShowingSkipDialog = false
    }

    func cancelEndRoutine() {
        isShowingEndDialog = false
    }

    func completeCurrentStep(inputText: String? = nil, transcript: String? = nil) {
        guard let step = currentStep else { return }

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
        guard let step = currentStep else { return }

        let result = RoutineStepResult(
            stepID: step.id,
            stepTitle: step.title,
            stepType: step.type,
            completedAt: nil,
            skipped: true
        )

        stepResults.append(result)
        isShowingSkipDialog = false
        moveToNextStep()
    }

    func finishStepCompletedScreen() {
        moveToNextStep()
    }

    func endRoutine() {
        isShowingEndDialog = false
        saveRun(endedEarly: true)
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
        let run = RoutineRun(
            routine: routine,
            startedAt: startedAt,
            completedAt: Date(),
            results: stepResults,
            endedEarly: endedEarly
        )

        do {
            try runRepository?.saveRun(run)
        } catch {
            errorMessage = "루틴 실행 기록을 저장하지 못했습니다."
        }

        screenState = .finished
    }
}
