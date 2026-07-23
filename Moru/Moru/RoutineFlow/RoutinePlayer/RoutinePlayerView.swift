//
//  RoutinePlayerView.swift
//  Moru
//

import Foundation
import SwiftUI

struct RoutinePlayerView: View {
    @State private var viewModel: RoutinePlayerViewModel
    @State private var speechInputController: SpeechInputController

    /// 완료 화면과 오늘의 기록 화면 사이의 전환 상태
    @State private var isShowingTodayRecord = false

    init(
        viewModel: RoutinePlayerViewModel,
        speechInputController: SpeechInputController = SpeechInputController()
    ) {
        _viewModel = State(initialValue: viewModel)
        _speechInputController = State(
            initialValue: speechInputController
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundView
                contentView
                dialogView
            }
            .overlay(alignment: .bottom) {
                if let errorMessage = viewModel.errorMessage {
                    saveErrorBanner(message: errorMessage)
                }
            }
            .interactiveDismissDisabled()
            .navigationBarBackButtonHidden(true)
            .task {
                viewModel.resolveRoutine()
            }
        }
        .onDisappear {
            speechInputController.cancel()
            viewModel.viewDidDisappear()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.screenState {
        case .resolving:
            resolvingView

        case .resolutionRetry(let reason):
            resolutionRetryView(reason: reason)

        case .terminalFailure(let reason):
            terminalFailureView(reason: reason)

        case .running(let step):
            runningView(step: step)

        case .stepCompleted(let step):
            RoutineStepCompletedView(
                stepTitle: step.title,
                isGuidancePlaying: viewModel.isGuidancePlaying
            ) {
                await viewModel.finishStepCompletedScreenAfterGuidance()
            }

        case .summary(let summary):
            summaryView(summary: summary)
        }
    }

    private var resolvingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(AppColor.orange250)

            Text("루틴을 준비하고 있어요.")
                .font(AppFont.body1NormalSemiBold)
                .foregroundStyle(AppColor.gray600)
        }
    }

    private func resolutionRetryView(
        reason: RoutineResolutionRetryReason
    ) -> some View {
        VStack(spacing: 20) {
            Text("루틴을 불러오지 못했어요.")
                .font(AppFont.title2Bold)
                .foregroundStyle(AppColor.gray600)

            Text(resolutionRetryMessage(for: reason))
                .font(AppFont.body1NormalMedium)
                .foregroundStyle(AppColor.gray500)
                .multilineTextAlignment(.center)

            Button {
                viewModel.retryResolution()
            } label: {
                Text("다시 시도")
                    .font(AppFont.body1NormalSemiBold)
                    .foregroundStyle(AppColor.grayWhite)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppColor.orange350)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(32)
    }

    private func terminalFailureView(
        reason: RoutineTerminalReason
    ) -> some View {
        VStack(spacing: 20) {
            Text("루틴을 실행할 수 없어요.")
                .font(AppFont.title2Bold)
                .foregroundStyle(AppColor.gray600)

            Text(terminalFailureMessage(for: reason))
                .font(AppFont.body1NormalMedium)
                .foregroundStyle(AppColor.gray500)
                .multilineTextAlignment(.center)

            Button {
                viewModel.continueAfterTerminalFailure()
            } label: {
                Text("계속")
                    .font(AppFont.body1NormalSemiBold)
                    .foregroundStyle(AppColor.grayWhite)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppColor.orange350)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(32)
    }

    // MARK: - Running

    private func runningView(
        step: RoutineStep
    ) -> some View {
        VStack(spacing: 0) {
            topBar

            progressSection
                .padding(.top, 24)

            Spacer()

            stepContent(for: step)

            Spacer()

            Button {
                viewModel.requestSkipStep()
            } label: {
                Text("건너뛰기")
                    .font(AppFont.label1NormalMedium)
                    .foregroundStyle(AppColor.gray300)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.bottom, 36)
        }
        .padding(.top, 24)
        .disabled(viewModel.isStepInteractionDisabled)
        .onAppear {
            viewModel.runnableContentDidAppear()
        }
    }

    @ViewBuilder
    private func stepContent(
        for step: RoutineStep
    ) -> some View {
        switch step.type {
        case .confirm:
            ConfirmStepContentView(
                step: step,
                isGuidancePlaying: viewModel.isGuidancePlaying,
                speechInputController: speechInputController
            ) { transcript in
                viewModel.completeCurrentStep(
                    transcript: transcript
                )
            }
            .id(step.id)

        case .timer:
            TimerStepContentView(
                step: step,
                isGuidancePlaying: viewModel.isGuidancePlaying
            ) {
                viewModel.completeCurrentStep()
            }
            .id(step.id)

        case .input:
            InputStepContentView(
                step: step,
                isGuidancePlaying: viewModel.isGuidancePlaying,
                speechInputController: speechInputController
            ) { transcript in
                viewModel.completeCurrentStep(
                    inputText: transcript,
                    transcript: transcript
                )
            }
            .id(step.id)
        }
    }

    // MARK: - Dialog

    @ViewBuilder
    private var dialogView: some View {
        switch viewModel.dialogState {
        case .some(.skipStep):
            SkipStepDialogView(
                onCancel: {
                    viewModel.cancelActiveDialog()
                },
                onConfirm: {
                    speechInputController.cancel()
                    viewModel.confirmActiveDialog()
                }
            )

        case .some(.exit(_)):
            EndRoutineDialogView(
                onCancel: {
                    viewModel.cancelActiveDialog()
                },
                onConfirm: {
                    speechInputController.cancel()
                    viewModel.confirmActiveDialog()
                }
            )

        case .none:
            EmptyView()
        }
    }

    // MARK: - Header

    private var topBar: some View {
        HStack {
            Button {
                viewModel.requestCloseRoutine()
            } label: {
                Text("닫기")
                    .font(AppFont.body1NormalMedium)
                    .foregroundStyle(AppColor.gray350)
                    .frame(width: 56, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("오늘의 루틴")
                .font(AppFont.body1NormalSemiBold)
                .foregroundStyle(AppColor.gray600)

            Spacer()

            Button {
                viewModel.requestEndRoutine()
            } label: {
                Text("종료")
                    .font(AppFont.body1NormalMedium)
                    .foregroundStyle(AppColor.gray350)
                    .frame(width: 56, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(
                value: viewModel.progressValue
            )
            .tint(AppColor.orange250)

            Text(viewModel.currentStepNumberText)
                .font(AppFont.caption1Medium)
                .foregroundStyle(AppColor.gray400)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Summary

    private func summaryView(
        summary: RoutineCompletionSummary
    ) -> some View {
        RoutineFinishedView(
            completionRate: summary.completionRate,
            consecutiveDays: viewModel.consecutiveDays,
            completedStepTitles: viewModel.completedStepTitles,
            onTapTodayRecord: {
                if summary.persistedRunID == nil {
                    isShowingTodayRecord = true
                } else {
                    speechInputController.cancel()
                    viewModel.requestSummaryRecord()
                }
            },
            onTapHome: {
                speechInputController.cancel()
                viewModel.requestSummaryExit()
            }
        )
        .navigationDestination(
            isPresented: $isShowingTodayRecord
        ) {
            TodayRoutineRecordView(
                date: summary.completedAt,
                completionRate: summary.completionRate,
                totalDurationSeconds: totalDurationSeconds(
                    for: summary
                ),
                wakeUpTime: summary.startedAt,
                results: viewModel.stepResults,
                onTapBack: {
                    isShowingTodayRecord = false
                },
                onTapHome: {
                    speechInputController.cancel()
                    viewModel.requestSummaryExit()
                }
            )
            .navigationBarBackButtonHidden(true)
        }
    }

    private func totalDurationSeconds(
        for summary: RoutineCompletionSummary
    ) -> Int {
        let duration = summary.completedAt
            .timeIntervalSince(summary.startedAt)

        return max(
            Int(duration.rounded(.up)),
            0
        )
    }

    // MARK: - Error Banner

    private func saveErrorBanner(
        message: String
    ) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(AppFont.body1NormalMedium)
                .foregroundStyle(AppColor.gray500)
                .multilineTextAlignment(.center)

            Button {
                viewModel.retrySavingRun()
            } label: {
                Text("다시 시도")
                    .font(AppFont.body1NormalSemiBold)
                    .foregroundStyle(AppColor.grayWhite)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(AppColor.orange350)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSavingRun)
        }
        .padding(20)
        .background(AppColor.grayWhite)
        .clipShape(
            RoundedRectangle(cornerRadius: 20)
        )
        .shadow(radius: 12, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Background

    private var backgroundView: some View {
        LinearGradient(
            colors: [
                AppColor.babyBlue50,
                AppColor.grayWhite
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Error Messages

    private func resolutionRetryMessage(
        for reason: RoutineResolutionRetryReason
    ) -> String {
        switch reason {
        case .repositoryUnavailable:
            return "저장된 루틴을 다시 불러와 주세요."
        }
    }

    private func terminalFailureMessage(
        for reason: RoutineTerminalReason
    ) -> String {
        switch reason {
        case .notFound:
            return "저장된 루틴을 찾을 수 없어요."

        case .ineligible(let ineligibilityReason):
            return ineligibilityMessage(
                for: ineligibilityReason
            )

        case .invalidCompletionSummary:
            return """
            루틴 실행 시간을 확인할 수 없어요.
            다시 시작해 주세요.
            """
        }
    }

    private func ineligibilityMessage(
        for reason: RoutineIneligibilityReason
    ) -> String {
        switch reason {
        case .inactive:
            return "비활성화된 루틴은 예약 실행할 수 없어요."

        case .alarmDisabled:
            return "알람이 켜진 루틴만 예약 실행할 수 있어요."

        case .noExecutableSteps:
            return "실행할 단계가 있는 루틴을 선택해 주세요."
        }
    }
}


#if DEBUG
@MainActor
private final class RoutinePlayerPreviewResolver:
    ResolveRoutineExecutionUseCaseProtocol {
    func execute(
        _ request: ResolveRoutineExecutionRequest
    ) -> RoutineExecutionResolution {
        .available(.mockMorningRoutine)
    }
}

@MainActor
private final class RoutinePlayerPreviewTrialFinalizer: TrialRoutineFinalizing {
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
private final class RoutinePlayerPreviewRegularFinalizer: RegularRoutineFinalizing {
    func finalize(
        _ request: SaveRoutineRunRequest
    ) throws -> RoutineCompletionSummary {
        return try makeRoutineCompletionSummary(
            routine: request.routine,
            persistedRunID: UUID(),
            startedAt: request.startedAt,
            completedAt: request.completedAt,
            results: request.results,
            endedEarly: request.endedEarly
        ).get()
    }
}

#Preview {
    RoutinePlayerView(
        viewModel: RoutinePlayerViewModel(
            request: TrialRoutineExecutionRequest(
                routineID: Routine.mockMorningRoutine.id
            ),
            resolver: RoutinePlayerPreviewResolver(),
            finalizer: RoutinePlayerPreviewTrialFinalizer(),
            presentationToken: UUID(),
            onEvent: { _, _ in }
        )
    )
}
#Preview("Regular") {
    RoutinePlayerView(
        viewModel: RoutinePlayerViewModel(
            request: RegularRoutineExecutionRequest(
                routineID: Routine.mockMorningRoutine.id,
                source: .manual
            ),
            resolver: RoutinePlayerPreviewResolver(),
            finalizer: RoutinePlayerPreviewRegularFinalizer(),
            presentationToken: UUID(),
            onEvent: { _, _ in }
        )
    )
}
#endif
