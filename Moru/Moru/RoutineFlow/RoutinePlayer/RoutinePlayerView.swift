//
//  RoutinePlayerView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import SwiftUI

struct RoutinePlayerView: View {
    @State private var viewModel: RoutinePlayerViewModel

    init(
        routine: Routine,
        dependencies: DependencyContainer
    ) {
        let useCase = SaveRoutineRunUseCase(
            routineRunRepository: dependencies.routineRunRepository
        )

        _viewModel = State(
            initialValue: RoutinePlayerViewModel(
                routine: routine,
                saveRoutineRunUseCase: useCase
            )
        )
    }

    init(
        routine: Routine,
        saveRoutineRunUseCase: any SaveRoutineRunUseCaseProtocol
    ) {
        _viewModel = State(
            initialValue: RoutinePlayerViewModel(
                routine: routine,
                saveRoutineRunUseCase: saveRoutineRunUseCase
            )
        )
    }

    var body: some View {
        ZStack {
            backgroundView

            contentView

            if viewModel.isShowingSkipDialog {
                SkipStepDialogView(
                    onCancel: {
                        viewModel.cancelSkipStep()
                    },
                    onConfirm: {
                        viewModel.skipCurrentStep()
                    }
                )
            }

            if viewModel.isShowingEndDialog {
                EndRoutineDialogView(
                    onCancel: {
                        viewModel.cancelEndRoutine()
                    },
                    onConfirm: {
                        viewModel.endRoutine()
                    }
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let errorMessage = viewModel.errorMessage {
                saveErrorBanner(message: errorMessage)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.screenState {
        case .running:
            runningView

        case .stepCompleted(let step):
            RoutineStepCompletedView(stepTitle: step.title) {
                viewModel.finishStepCompletedScreen()
            }

        case .finished(let savedRun):
            RoutineFinishedView(
                routineName: savedRun.routineName,
                completionRate: Int(
                    (savedRun.completionRate * 100).rounded()
                ),
                completedStepCount: savedRun.results
                    .filter(\.isCompleted)
                    .count,
                skippedStepCount: savedRun.results
                    .filter(\.skipped)
                    .count,
                onTapTodayRecord: {
                    // TODO: History / Today Detail 화면으로 이동 연결
                }
            )
        }
    }

    private var runningView: some View {
        VStack(spacing: 0) {
            topBar

            progressSection
                .padding(.top, 24)

            Spacer()

            if let step = viewModel.currentStep {
                stepContent(for: step)
            } else {
                Text("실행할 단계가 없습니다.")
                    .font(AppFont.body1NormalSemiBold)
                    .foregroundStyle(AppColor.grayWhite)
            }

            Spacer()

            Button {
                viewModel.requestSkipStep()
            } label: {
                Text("건너뛰기")
                    .font(AppFont.body1NormalSemiBold)
                    .foregroundStyle(AppColor.grayWhite.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.bottom, 36)
        }
        .padding(.top, 24)
    }

    private var topBar: some View {
        HStack {
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
        .overlay(alignment: .leading) {
            Color.clear
                .frame(width: 56, height: 40)
        }
        .padding(.horizontal, 20)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: viewModel.progressValue)
                .tint(AppColor.orange250)

            Text(viewModel.currentStepNumberText)
                .font(AppFont.caption1Medium)
                .foregroundStyle(AppColor.gray400)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func stepContent(for step: RoutineStep) -> some View {
        switch step.type {
        case .confirm:
            ConfirmStepContentView(
                step: step,
                onComplete: {
                    viewModel.completeCurrentStep()
                }
            )

        case .timer:
            TimerStepContentView(
                step: step,
                onComplete: {
                    viewModel.completeCurrentStep()
                }
            )

        case .input:
            InputStepContentView(
                step: step,
                onComplete: { inputText in
                    viewModel.completeCurrentStep(inputText: inputText)
                }
            )
        }
    }
    
    private func saveErrorBanner(message: String) -> some View {
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
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 12, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

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
}

#if DEBUG
#Preview {
    RoutinePlayerView(
        routine: .mockMorningRoutine,
        dependencies: .mock()
    )
}
#endif
