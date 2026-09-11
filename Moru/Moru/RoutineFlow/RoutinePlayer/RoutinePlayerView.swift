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
                    .overlay(alignment: .bottom) {
                        if let errorMessage = viewModel.errorMessage {
                            saveErrorBanner(message: errorMessage)
                        }
                    }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showsProgressChrome {
                    progressSection
                        .padding(.top, viewModel.isTrialExecution ? 12 : 8)
                        .padding(.bottom, 8)
                }
            }
            .toolbar {
                if !viewModel.isTrialExecution && showsProgressChrome {
                    ToolbarItem(placement: .cancellationAction) {
                        closeButton
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        endButton
                    }
                }
            }
            .toolbar(
                viewModel.isTrialExecution ? .hidden : .automatic,
                for: .navigationBar
            )
            .navigationTitle("오늘의 루틴")
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                activeDialogCopy?.title ?? "",
                isPresented: Binding(
                    get: { viewModel.dialogState != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.cancelActiveDialog()
                        }
                    }
                ),
                presenting: activeDialogCopy
            ) { copy in
                Button(copy.cancelTitle, role: .cancel) {
                    viewModel.cancelActiveDialog()
                }
                Button(
                    copy.confirmTitle,
                    role: isDiscardUnsavedRunDialog ? .destructive : nil
                ) {
                    speechInputController.cancel()
                    viewModel.confirmActiveDialog()
                }
            } message: { copy in
                Text(copy.message)
            }
            .interactiveDismissDisabled()
            .navigationBarBackButtonHidden(true)
            .task {
                viewModel.resolveRoutine()
            }
        }
        .onAppear {
            // 루틴은 폰을 내려놓고 하는 것이라 자동 잠금이 실행을 끊으면 안 된다.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
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
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willEnterForegroundNotification
            )
        ) { _ in
            viewModel.runtimeDidResume()
        }
    }

    // MARK: - Content

    /// 진행바(그리고 체험이 아닐 때는 닫기·종료)를 보여줄 상태인지.
    /// viewModel.progressValue/currentStepNumberText와 같은 상태 집합이다.
    private var showsProgressChrome: Bool {
        switch viewModel.screenState {
        case .preparingServerVoice, .running, .stepCompleted:
            return true
        case .resolving, .resolutionRetry, .terminalFailure, .summary:
            return false
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.screenState {
        case .resolving:
            resolvingView

        case .resolutionRetry(let reason):
            resolutionRetryView(reason: reason)

        case .terminalFailure(let reason):
            terminalFailureView(reason: reason)

        case .preparingServerVoice(let step):
            serverVoicePreparationView(step: step)

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

            MoruButton("다시 시도") {
                viewModel.retryResolution()
            }
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

            MoruButton("계속") {
                viewModel.continueAfterTerminalFailure()
            }
        }
        .padding(32)
    }

    // MARK: - Running

    private func serverVoicePreparationView(
        step: RoutineStep
    ) -> some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    Spacer(minLength: 48)

                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(AppColor.orange250)

                        Text("서버 음성을 준비하고 있어요.")
                            .font(AppFont.title2Bold)
                            .foregroundStyle(AppColor.gray600)
                            .multilineTextAlignment(.center)

                        Text("최대 30초만 기다린 뒤 루틴을 시작할게요.")
                            .font(AppFont.body1NormalMedium)
                            .foregroundStyle(AppColor.gray500)
                            .multilineTextAlignment(.center)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(step.title) 서버 음성을 준비하고 있어요."
                    )
                    .padding(.horizontal, 32)

                    Spacer(minLength: 48)
                }
                .frame(
                    minHeight: geometry.size.height,
                    alignment: .top
                )
            }
            .scrollIndicators(.hidden)
        }
    }

    private func runningView(
        step: RoutineStep
    ) -> some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 20)

                    // 단계 게이트는 단계 콘텐츠에만 건다. 상단바의 닫기·종료는
                    // 저장 실패 중에도 눌러서 나갈 수 있어야 한다.
                    stepContent(for: step)
                        .disabled(viewModel.isStepInteractionDisabled)

                }
                .frame(
                    minHeight: geometry.size.height,
                    alignment: .top
                )
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            viewModel.runnableContentDidAppear()
        }
    }

    private func stepCompletedView(
        step: RoutineStep
    ) -> some View {
        RoutineStepCompletedView(
            stepTitle: step.title,
            isGuidancePlaying: viewModel.isGuidancePlaying
        ) {
            await viewModel.finishStepCompletedScreenAfterGuidance()
        }
        .offset(y: 12)
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

    /// 현재 dialogState에 맞는 문구. 네이티브 alert는 바깥을 탭해도 닫히지 않는다(시스템 규칙).
    private var activeDialogCopy: RoutinePlayerDialogCopy? {
        switch viewModel.dialogState {
        case .skipStep:
            RoutinePlayerDialogCopy.skipStep
        case .exit(let exit):
            RoutinePlayerDialogCopy.exit(exit)
        case .discardUnsavedRun:
            RoutinePlayerDialogCopy.discardUnsavedRun
        case nil:
            nil
        }
    }

    /// 되돌릴 수 없는 동작만 destructive로 강조한다(삭제하기·기록 없이 나가기).
    private var isDiscardUnsavedRunDialog: Bool {
        if case .discardUnsavedRun = viewModel.dialogState {
            return true
        }
        return false
    }

    // MARK: - Header

    /// 닫기(X): 기록을 저장하고 요약 없이 홈으로. "종료"와 역할이 다르므로 아이콘으로 구분한다.
    private var closeButton: some View {
        Button {
            viewModel.requestCloseRoutine()
        } label: {
            Image(systemName: "xmark")
        }
        .accessibilityLabel("닫기")
        .accessibilityHint("지금까지의 진행을 기록하고 홈으로 돌아갑니다")
    }

    private var endButton: some View {
        Button("종료") {
            viewModel.requestEndRoutine()
        }
        .accessibilityHint("지금까지의 결과를 저장하고 완료 화면으로 이동합니다")
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MoruColor.progressTrack)

                    Capsule()
                        .fill(MoruColor.accent)
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
            stepResults: viewModel.summaryStepResults,
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
                results: viewModel.summaryStepResults,
                onTapHome: {
                    speechInputController.cancel()
                    viewModel.requestSummaryExit()
                }
            )
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

            MoruButton("다시 시도", isEnabled: !viewModel.isSavingRun) {
                viewModel.retrySavingRun()
            }

            MoruButton(
                RoutinePlayerDialogCopy.discardUnsavedRun.confirmTitle,
                style: .text,
                isEnabled: viewModel.hasUnsavedRun
            ) {
                viewModel.requestDiscardUnsavedRun()
            }
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
