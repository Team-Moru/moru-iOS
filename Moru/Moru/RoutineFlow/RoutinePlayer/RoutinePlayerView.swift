//
//  RoutinePlayerView.swift
//  Moru
//

import Foundation
import SwiftUI
enum RoutinePlayerAccessibility {
  static let stepTitle = "routinePlayer.step.title"
  static let input = "routinePlayer.input"
  static let stepTitleLabel = "오늘의 루틴"
  static func inputLabel(for step: RoutineStep) -> String {
    step.title
  }
}

struct RoutinePlayerView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var viewModel: RoutinePlayerViewModel

  init(viewModel: RoutinePlayerViewModel) {
    _viewModel = State(initialValue: viewModel)
  }

  private var topBarButtonFrame: CGSize? {
    guard !dynamicTypeSize.isAccessibilitySize else {
      return nil
    }
    return CGSize(width: 56, height: 40)
  }

  private var topBarButtonMinimumHeight: CGFloat? {
    dynamicTypeSize.isAccessibilitySize ? 44 : nil
  }

  var body: some View {
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
      RoutineStepCompletedView(stepTitle: step.title) {
        viewModel.finishStepCompletedScreen()
      }

    case .summary(let presentation):
      summaryView(presentation)
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

  private func runningView(step: RoutineStep) -> some View {
    VStack(spacing: 0) {
      topBar

      progressSection
        .padding(.top, 24)

      GeometryReader { proxy in
        ScrollView {
          stepContent(for: step)
            .id(step.id)
            .frame(
              maxWidth: .infinity,
              minHeight: proxy.size.height
            )
        }
        .scrollIndicators(.hidden)
      }

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
    .safeAreaPadding(.top, 24)
    .disabled(viewModel.isStepInteractionDisabled)
    .onAppear {
      viewModel.runnableContentDidAppear()
    }
  }

  @ViewBuilder
  private var dialogView: some View {
    switch viewModel.dialogState {
    case .some(.skipStep):
      SkipStepDialogView(
        onCancel: {
          viewModel.cancelActiveDialog()
        },
        onConfirm: {
          viewModel.confirmActiveDialog()
        }
      )

    case .some(.exit(_)):
      EndRoutineDialogView(
        onCancel: {
          viewModel.cancelActiveDialog()
        },
        onConfirm: {
          viewModel.confirmActiveDialog()
        }
      )

    case .none:
      EmptyView()
    }
  }

  private var topBar: some View {
    HStack {
      Button {
        viewModel.requestCloseRoutine()
      } label: {
        Text("닫기")
          .font(AppFont.body1NormalMedium)
          .foregroundStyle(AppColor.gray350)
          .fixedSize(
            horizontal: dynamicTypeSize.isAccessibilitySize,
            vertical: dynamicTypeSize.isAccessibilitySize
          )
          .frame(
            width: topBarButtonFrame?.width,
            height: topBarButtonFrame?.height
          )
          .frame(minHeight: topBarButtonMinimumHeight)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Spacer()

      Text(RoutinePlayerAccessibility.stepTitleLabel)
        .font(AppFont.body1NormalSemiBold)
        .foregroundStyle(AppColor.gray600)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
        .accessibilityIdentifier(RoutinePlayerAccessibility.stepTitle)
        .accessibilityLabel(RoutinePlayerAccessibility.stepTitleLabel)

      Spacer()

      Button {
        viewModel.requestEndRoutine()
      } label: {
        Text("종료")
          .font(AppFont.body1NormalMedium)
          .foregroundStyle(AppColor.gray350)
          .fixedSize(
            horizontal: dynamicTypeSize.isAccessibilitySize,
            vertical: dynamicTypeSize.isAccessibilitySize
          )
          .frame(
            width: topBarButtonFrame?.width,
            height: topBarButtonFrame?.height
          )
          .frame(minHeight: topBarButtonMinimumHeight)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
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
      ConfirmStepContentView(step: step) {
        viewModel.completeCurrentStep()
      }

    case .timer:
      TimerStepContentView(step: step) {
        viewModel.completeCurrentStep()
      }

    case .input:
      InputStepContentView(step: step) { inputText in
        viewModel.completeCurrentStep(inputText: inputText)
      }
    }
  }

  @ViewBuilder
  private func summaryView(
    _ presentation: RoutineCompletionPresentation
  ) -> some View {
    switch presentation {
    case .trial(let summary):
      RoutineFinishedView(
        routineName: summary.routineName,
        completionRate: Int((summary.completionRate * 100).rounded()),
        completedStepCount: summary.completedStepCount,
        skippedStepCount: summary.skippedStepCount,
        actionConfiguration: .trialHomeOnly,
        onAction: { action in
          switch action {
          case .home:
            viewModel.requestSummaryHome()

          case .record:
            assertionFailure("Trial completion cannot record a routine run.")
          }
        },
        isActionDisabled: viewModel.isSummaryActionDisabled
      )

    case .regular(let result):
      let summary = result.summary

      RoutineFinishedView(
        routineName: summary.routineName,
        completionRate: Int((summary.completionRate * 100).rounded()),
        completedStepCount: summary.completedStepCount,
        skippedStepCount: summary.skippedStepCount,
        actionConfiguration: .regularRecordAndHome,
        onAction: { action in
          switch action {
          case .record:
            viewModel.requestSummaryRecord()

          case .home:
            viewModel.requestSummaryHome()
          }
        },
        isActionDisabled: viewModel.isSummaryActionDisabled
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
      return ineligibilityMessage(for: ineligibilityReason)

    case .invalidCompletionSummary:
      return "루틴 실행 시간을 확인할 수 없어요. 다시 시작해 주세요."
    case .missingPersistedRunID:
      return "저장된 루틴 실행 기록을 확인할 수 없어요. 다시 시작해 주세요."
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

    case .invalidTimerDuration:
      return "타이머 단계의 시간이 설정되지 않았거나 올바르지 않아요. 루틴을 수정한 뒤 다시 시작해 주세요."
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
  ) throws -> RegularRoutineCompletionResult {
    let persistedRunID = UUID()
    let summary = try makeRoutineCompletionSummary(
      routine: request.routine,
      persistedRunID: persistedRunID,
      startedAt: request.startedAt,
      completedAt: request.completedAt,
      results: request.results,
      endedEarly: request.endedEarly
    ).get()

    guard let result = RegularRoutineCompletionResult(summary) else {
      throw RegularRoutineFinalizationError.missingPersistedRunID
    }

    return result
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
