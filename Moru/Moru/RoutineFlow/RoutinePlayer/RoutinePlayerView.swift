//
//  RoutinePlayerView.swift
//  Moru
//

import Foundation
import SwiftUI
import UIKit

struct RoutinePlayerView: View {
    @State private var viewModel: RoutinePlayerViewModel
    @State private var speechInputController: SpeechInputController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didEnterBackgroundNotification
            )
        ) { _ in
            speechInputController.cancel()
            viewModel.runtimeDidInterrupt()
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

        case .serverVoicePreparing(let step):
            serverVoicePreparingView(step: step)

        case .serverVoiceRetry(let step):
            serverVoiceRetryView(step: step)

        case .running(let step):
            runningView(step: step)

        case .stepCompleted(let step):
            stepCompletedView(step: step)

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

    private func serverVoicePreparingView(step: RoutineStep) -> some View {
        VStack(spacing: 20) {
            if !viewModel.isTrialExecution {
                topBar
            }

            Spacer(minLength: 0)

            ProgressView()
                .tint(AppColor.orange250)

            Text("선택한 서버 음성을 준비하고 있어요.")
                .font(AppFont.title2Bold)
                .foregroundStyle(AppColor.gray600)

            Text("음성 준비가 끝나면 이 단계를 시작할게요.")
                .font(AppFont.body1NormalMedium)
                .foregroundStyle(AppColor.gray500)
                .multilineTextAlignment(.center)

            Text(step.title)
                .font(AppFont.pretendardSemiBold(size: 16, relativeTo: .body))
                .foregroundStyle(AppColor.gray400)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
        .padding(32)
        .accessibilityIdentifier("routine-server-voice-preparing")
    }

    private func serverVoiceRetryView(step: RoutineStep) -> some View {
        VStack(spacing: 20) {
            if !viewModel.isTrialExecution {
                topBar
            }

            Spacer(minLength: 0)

            Text("서버 음성을 아직 준비하지 못했어요.")
                .font(AppFont.title2Bold)
                .foregroundStyle(AppColor.gray600)

            Text(
                "잠시 후 다시 시도하거나, "
                    + "음성 없이 이 단계를 시작할 수 있어요."
            )
                .font(AppFont.body1NormalMedium)
                .foregroundStyle(AppColor.gray500)
                .multilineTextAlignment(.center)

            Text(step.title)
                .font(AppFont.pretendardSemiBold(size: 16, relativeTo: .body))
                .foregroundStyle(AppColor.gray400)
                .multilineTextAlignment(.center)

            Button {
                viewModel.retryServerVoiceGuidance()
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
            .accessibilityIdentifier("routine-server-voice-retry")

            Button {
                viewModel.continueWithoutServerVoice()
            } label: {
                Text("음성 없이 계속")
                    .font(AppFont.body1NormalSemiBold)
                    .foregroundStyle(AppColor.gray500)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppColor.gray100)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("routine-server-voice-continue-without-audio")

            Spacer(minLength: 0)
        }
        .padding(32)
        .accessibilityIdentifier("routine-server-voice-retry-state")
    }

    // MARK: - Running

    private func runningView(
        step: RoutineStep
    ) -> some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    if !viewModel.isTrialExecution {
                        topBar
                    }

                    progressSection
                        .padding(
                            .top,
                            viewModel.isTrialExecution ? 28 : 32
                        )

                    Spacer()
                        .frame(
                            height: viewModel.isTrialExecution ? 70 : 20
                        )

                    stepContent(for: step)

                }
                .frame(
                    minHeight: geometry.size.height,
                    alignment: .top
                )
            }
            .scrollIndicators(.hidden)
        }
        .disabled(viewModel.isStepInteractionDisabled)
        .onAppear {
            viewModel.runnableContentDidAppear()
        }
    }

    private func stepCompletedView(
        step: RoutineStep
    ) -> some View {
        ZStack(alignment: .top) {
            RoutineStepCompletedView(
                stepTitle: step.title,
                isGuidancePlaying: viewModel.isGuidancePlaying
            ) {
                await viewModel.finishStepCompletedScreenAfterGuidance()
            }
            .offset(y: 12)

            VStack(spacing: 0) {
                if !viewModel.isTrialExecution {
                    topBar
                }

                progressSection
                    .padding(
                        .top,
                        viewModel.isTrialExecution ? 28 : 32
                    )
            }
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
                isAutomaticStartBlocked: viewModel.dialogState != nil,
                speechInputController: speechInputController,
                waitUntilGuidanceFinishes: {
                    await viewModel.waitUntilIntroFinishes(for: step.id)
                },
                onNoSpeechReminder: {
                    await viewModel.playNoSpeechReminder(for: step.id)
                },
                onComplete: { transcript in
                    viewModel.completeCurrentStep(
                        transcript: transcript
                    )
                },
                onAutomaticSkip: {
                    viewModel.skipCurrentStep()
                },
                onSkip: {
                    viewModel.requestSkipStep()
                }
            )
            .id(step.id)

        case .timer:
            TimerStepContentView(
                step: step,
                isGuidancePlaying: viewModel.isGuidancePlaying,
                onComplete: {
                    viewModel.completeCurrentStep()
                },
                onCountdown: { seconds in
                    viewModel.timerCountdownDidReach(
                        seconds,
                        stepID: step.id
                    )
                },
                onSkip: {
                    viewModel.requestSkipStep()
                }
            )
            .id(step.id)

        case .input:
            InputStepContentView(
                step: step,
                isGuidancePlaying: viewModel.isGuidancePlaying,
                isAutomaticStartBlocked: viewModel.dialogState != nil,
                speechInputController: speechInputController,
                waitUntilGuidanceFinishes: {
                    await viewModel.waitUntilIntroFinishes(for: step.id)
                },
                onNoSpeechReminder: {
                    await viewModel.playNoSpeechReminder(for: step.id)
                },
                onComplete: { transcript in
                    viewModel.completeCurrentStep(
                        inputText: transcript,
                        transcript: transcript
                    )
                },
                onAutomaticSkip: {
                    viewModel.skipCurrentStep()
                },
                onSkip: {
                    viewModel.requestSkipStep()
                }
            )
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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    topBarTitle

                    HStack {
                        closeButton
                        Spacer()
                        endButton
                    }
                }
                .padding(.vertical, 8)
            } else {
                HStack {
                    closeButton

                    Spacer()

                    topBarTitle

                    Spacer()

                    endButton
                }
                .frame(height: 40)
            }
        }
        .padding(.horizontal, 20)
    }

    private var closeButton: some View {
        Button {
            viewModel.requestCloseRoutine()
        } label: {
            Text("닫기")
                .font(AppFont.pretendardMedium(size: 16, relativeTo: .body))
                .foregroundStyle(AppColor.gray350)
                .frame(minWidth: 56, minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var topBarTitle: some View {
        Text("오늘의 루틴")
            .font(AppFont.pretendardSemiBold(size: 18, relativeTo: .body))
            .foregroundStyle(AppColor.gray600)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var endButton: some View {
        Button {
            viewModel.requestEndRoutine()
        } label: {
            Text("종료")
                .font(AppFont.pretendardMedium(size: 16, relativeTo: .body))
                .foregroundStyle(AppColor.gray350)
                .frame(minWidth: 56, minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MoruPilotColor.progressTrack)

                    Capsule()
                        .fill(MoruPilotColor.accent)
                        .frame(
                            width: geometry.size.width
                              * min(max(viewModel.progressValue, 0), 1)
                        )
                }
            }
            .frame(height: 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("루틴 진행 상황")
            .accessibilityValue(viewModel.currentStepNumberText)

            Text(viewModel.currentStepNumberText)
                .font(
                    AppFont.pretendardMedium(size: 12, relativeTo: .caption2)
                )
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
            streak: summary.streak,
            stepResults: viewModel.stepResults,
            isTrial: summary.persistedRunID == nil,
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
                AppColor.babyBlue100.opacity(0.52),
                AppColor.babyBlue50,
                AppColor.babyBlue50
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

@MainActor
private extension RoutinePlayerViewModel {
    static func serverVoiceRetryPreview() -> RoutinePlayerViewModel {
        let viewModel = RoutinePlayerViewModel(
            request: RegularRoutineExecutionRequest(
                routineID: Routine.mockMorningRoutine.id,
                source: .manual
            ),
            resolver: RoutinePlayerPreviewResolver(),
            finalizer: RoutinePlayerPreviewRegularFinalizer(),
            presentationToken: UUID(),
            onEvent: { _, _ in }
        )
        viewModel.applyServerVoiceRetryPreviewState()
        return viewModel
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
#Preview("Server voice retry") {
    RoutinePlayerView(
        viewModel: .serverVoiceRetryPreview()
    )
}
#endif
