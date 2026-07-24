//
//  OnboardingFlowView.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import SwiftUI

@MainActor
struct OnboardingFlowView: View {
  static let recommendedRootAccessibilityIdentifier =
    "routine.creation.recommended.flow"
  static let cancelAccessibilityIdentifier =
    "routine.creation.recommended.cancel"

  @StateObject private var viewModel: OnboardingViewModel

  init(viewModel: OnboardingViewModel) {
    _viewModel = StateObject(wrappedValue: viewModel)
  }

  var body: some View {
    VStack(spacing: 0) {
      if viewModel.progressIndex != nil || viewModel.canCancel {
        OnboardingHeaderView(viewModel: viewModel)
      }

      if viewModel.step == .completion || viewModel.step == .organizing {
        stepContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView(showsIndicators: false) {
          stepContent
            .padding(.horizontal, MoruPilotSpacing.twenty)
            .padding(.top, MoruPilotSpacing.thirtyTwo)
            .padding(.bottom, AppSpacing.thirtySix)
        }
        .defaultScrollAnchor(.top)
      }

      if viewModel.step.showsFooter {
        OnboardingFooterView(viewModel: viewModel)
      }
    }
    .background(OnboardingBackgroundView())
    .accessibilityIdentifier(
      viewModel.flowMode == .recommendedAddition
        ? Self.recommendedRootAccessibilityIdentifier
        : ""
    )
    .onAppear {
      _ = viewModel.refreshPreview()
    }
    .overlay {
      if let weekdayConflict = viewModel.weekdayConflict {
        weekdayConflictDialogOverlay(weekdayConflict)
      }
    }
  }

  @ViewBuilder
  private var stepContent: some View {
    switch viewModel.step {
    case .experience:
      RoutineExperienceQuestionView(viewModel: viewModel)
    case .goals:
      RoutineGoalSelectionView(viewModel: viewModel)
    case .suggestedRoutine:
      SuggestedRoutinePreviewView(viewModel: viewModel)
    case .duration:
      RoutineDurationPreviewView(viewModel: viewModel)
    case .freeform:
      RoutineFreeformInputView(viewModel: viewModel)
    case .organizing:
      RoutineOrganizingView(viewModel: viewModel)
    case .review:
      RoutineReviewView(viewModel: viewModel)
    case .alarm:
      OnboardingAlarmSettingView(viewModel: viewModel)
    case .voice:
      OnboardingVoiceSelectionView(viewModel: viewModel)
    case .completion:
      OnboardingCompletionView(viewModel: viewModel)
    }
  }

  private func weekdayConflictDialogOverlay(
    _ conflict: RoutineWeekdayConflictState
  ) -> some View {
    ZStack {
      AppColor.grayBlack
        .opacity(0.22)
        .ignoresSafeArea()

      MoruDialog(
        title: "다른 루틴에서 사용 중",
        message: [
          "\(conflict.weekdayText)은 알림이 설정된",
          "다른 루틴이 이미 있어요.",
          "추천 루틴으로 요일을 변경하시겠어요?",
        ].joined(separator: "\n"),
        primaryTitle: "괜찮아요",
        secondaryTitle: "변경하기",
        primaryAction: viewModel.keepExistingWeekdayScheduleButtonDidTap,
        secondaryAction: viewModel.resolveWeekdayConflictButtonDidTap
      )
    }
  }
}

private struct OnboardingHeaderView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      if viewModel.canCancel {
        HStack {
          Spacer()

          Button("취소", action: viewModel.cancelButtonDidTap)
            .onboardingTextStyle(.c1)
            .foregroundStyle(MoruPilotColor.textSecondary)
            .accessibilityIdentifier(
              OnboardingFlowView.cancelAccessibilityIdentifier
            )
        }
      }

      if let progressIndex = viewModel.progressIndex {
        MoruProgressBar(
          current: progressIndex,
          total: viewModel.progressTotal,
          componentStyle: .figmaPilot
        )
        .dynamicTypeSize(.medium)
      }
    }
    .padding(.horizontal, MoruPilotSpacing.twenty)
    .padding(.top, MoruPilotSpacing.sixteen)
  }
}

private struct OnboardingFooterView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    VStack(spacing: MoruPilotSpacing.eight) {
      if let errorMessage = viewModel.errorMessage {
        Text(errorMessage)
          .onboardingTextStyle(.c2)
          .foregroundStyle(AppColor.coral300)
          .multilineTextAlignment(.center)
      }

      Button {
        viewModel.primaryButtonDidTap()
      } label: {
        HStack(spacing: AppSpacing.xs) {
          if viewModel.isSaving {
            ProgressView()
              .tint(AppColor.grayWhite)
          }

          Text(viewModel.primaryButtonTitle)
            .onboardingTextStyle(.b4.weight(.semiBold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .foregroundStyle(AppColor.grayWhite)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(
          viewModel.canAdvance
            ? MoruPilotColor.accent
            : MoruPilotColor.textTertiary
        )
        .clipShape(
          RoundedRectangle(cornerRadius: MoruPilotRadius.pill)
        )
      }
      .buttonStyle(.plain)
      .disabled(!viewModel.canAdvance)
      .dynamicTypeSize(.medium)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, MoruPilotSpacing.twenty)
    .padding(.top, MoruPilotSpacing.sixteen)
    .padding(.bottom, viewModel.step == .completion ? 0 : MoruPilotSpacing.eight)
    .background(
      LinearGradient(
        colors: [
          MoruPilotColor.canvas.opacity(0),
          MoruPilotColor.canvas,
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }
}

private struct OnboardingBackgroundView: View {
  var body: some View {
    LinearGradient(
      colors: [
        AppColor.grayWhite,
        MoruPilotColor.canvas,
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea()
  }
}

private enum OnboardingSurface {
  static let card = AppColor.grayWhite
  static let input = AppColor.grayWhite
  static let listRow = AppColor.grayWhite
}

private struct OnboardingStepLayout<Content: View>: View {
  let title: String
  let subtitle: String
  var titleSpacing: CGFloat = AppSpacing.fiftySix
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: titleSpacing) {
      VStack(alignment: .leading, spacing: AppSpacing.xs) {
        Text(title)
          .onboardingTextStyle(.h2.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textStrong)
          .fixedSize(horizontal: false, vertical: true)

        if !subtitle.isEmpty {
          Text(subtitle)
            .onboardingTextStyle(.c1)
            .foregroundStyle(MoruPilotColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct RoutineExperienceQuestionView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    OnboardingStepLayout(
      title: "루틴 경험이\n있으신가요?",
      subtitle: OnboardingCopy.experienceSubtitle,
      titleSpacing: 68
    ) {
      VStack(spacing: MoruPilotSpacing.twelve) {
        ForEach(RoutineExperience.allCases) { experience in
          OnboardingOptionButton(
            title: experience.title,
            subtitle: OnboardingCopy.experienceDescription(for: experience),
            isSelected: false
          ) {
            viewModel.selectExperience(experience)
            viewModel.primaryButtonDidTap()
          }
        }
      }
    }
  }
}

private struct RoutineGoalSelectionView: View {
  @ObservedObject var viewModel: OnboardingViewModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    OnboardingStepLayout(
      title: "어떤 목표로\n시작할까요?",
      subtitle: "",
      titleSpacing: AppSpacing.fortyEight
    ) {
      LazyVGrid(columns: columns, spacing: MoruPilotSpacing.twelve) {
        ForEach(OnboardingDraft.goalOptions) { option in
          Button {
            viewModel.toggleGoal(tag: option.tag)
          } label: {
            HStack(spacing: MoruPilotSpacing.twelve) {
              MoruSelectionIcon(icon: option.icon)
                .frame(width: 32, height: 32)

              VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
                Text(option.title)
                  .onboardingTextStyle(.b2.weight(.semiBold))
                  .foregroundStyle(MoruPilotColor.textStrong)
                  .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                  .minimumScaleFactor(0.8)

                Text(option.subtitle)
                  .onboardingTextStyle(.c1.weight(.semiBold))
                  .foregroundStyle(MoruPilotColor.textSecondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .frame(
              maxWidth: .infinity,
              minHeight: dynamicTypeSize.isAccessibilitySize ? 132 : 104,
              alignment: .leading
            )
            .padding(.horizontal, MoruPilotSpacing.sixteen)
            .background(OnboardingSurface.card)
            .overlay(
              RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard)
                .stroke(
                  viewModel.draft.selectedGoalTags.contains(option.tag)
                    ? MoruPilotColor.accent
                    : MoruPilotColor.border,
                  lineWidth: 1.5
                )
            )
            .clipShape(
              RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard)
            )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var columns: [GridItem] {
    if dynamicTypeSize.isAccessibilitySize {
      return [GridItem(.flexible())]
    }

    return [
      GridItem(.flexible(), spacing: MoruPilotSpacing.twelve),
      GridItem(.flexible()),
    ]
  }
}

private struct SuggestedRoutinePreviewView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    OnboardingStepLayout(
      title: "모루가 추천하는\n나만의 루틴이에요",
      subtitle: "",
      titleSpacing: AppSpacing.seventyTwo
    ) {
      if let routine = viewModel.validatedPreviewRoutine {
        VStack(spacing: AppSpacing.lg) {
          RoutineMetaPill(
            goalTitle: viewModel.draft.primaryGoalTitle,
            stepCount: routine.steps.count,
            durationMinutes: OnboardingDuration.totalMinutes(for: routine)
          )

          RoutineStepListCard(routine: routine)
        }
      } else {
        PreviewUnavailableState(errorMessage: viewModel.errorMessage)
      }
    }
  }
}

private struct RoutineDurationPreviewView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    if let routine = viewModel.validatedPreviewRoutine {
      VStack(alignment: .leading, spacing: AppSpacing.xl) {
        Text(
          "예상 루틴 시간은\n\(Text("\(OnboardingDuration.totalMinutes(for: routine))분").foregroundColor(MoruPilotColor.accent))이에요"
        )
        .onboardingTextStyle(.h2.weight(.semiBold))
        .foregroundColor(MoruPilotColor.textStrong)
        .fixedSize(horizontal: false, vertical: true)

        Image(AppImage.moruOnboardingClock)
          .resizable()
          .scaledToFit()
          .frame(width: 240, height: 240)
          .frame(maxWidth: .infinity)
      }
    } else {
      OnboardingStepLayout(
        title: "루틴 미리보기를\n불러올 수 없어요",
        subtitle: "",
        titleSpacing: AppSpacing.fortyEight
      ) {
        PreviewUnavailableState(errorMessage: viewModel.errorMessage)
      }
    }
  }
}

private struct RoutineFreeformInputView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    OnboardingStepLayout(
      title: "원하는 루틴을\n입력해주세요",
      subtitle: OnboardingCopy.freeformSubtitle,
      titleSpacing: AppSpacing.forty
    ) {
      VStack(alignment: .leading, spacing: AppSpacing.md) {
        ZStack(alignment: .topLeading) {
          if viewModel.draft.freeformText.isEmpty {
            Text("예) 일어나면 물 마시고, 스트레칭 하고, 일기 쓰고,\n오늘 할 일 미리 확인하기")
              .onboardingTextStyle(.c1)
              .foregroundStyle(MoruPilotColor.textTertiary)
              .padding(AppSpacing.md)
          }

          TextEditor(text: $viewModel.draft.freeformText)
            .font(
              .custom(
                MoruTextWeight.medium.rawValue,
                size: MoruTextStyle.c1.fontSize,
                relativeTo: MoruTextStyle.c1.relativeTextStyle
              )
            )
            .foregroundStyle(MoruPilotColor.textPrimary)
            .frame(minHeight: 200)
            .padding(AppSpacing.sm)
            .scrollContentBackground(.hidden)
            .background(Color.clear)

          Text("\(min(viewModel.draft.freeformText.count, 200))/200")
            .onboardingTextStyle(.c2)
            .foregroundStyle(MoruPilotColor.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(AppSpacing.md)
            .allowsHitTesting(false)
        }
        .background(OnboardingSurface.input)
        .overlay(
          RoundedRectangle(cornerRadius: MoruPilotRadius.card)
            .stroke(MoruPilotColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.card))

        FlowLayout(spacing: AppSpacing.xs) {
          ForEach(OnboardingDraft.keywordOptions, id: \.self) { keyword in
            Button {
              viewModel.toggleKeyword(keyword)
            } label: {
              MoruChip(
                title: keyword,
                isSelected: viewModel.draft.selectedKeywords.contains(keyword)
              )
            }
            .buttonStyle(.plain)
          }
        }

        Text("* 위 키워드를 탭해서 빠르게 추가해보세요")
          .onboardingTextStyle(.c2.weight(.regular))
          .foregroundStyle(MoruPilotColor.textTertiary)
      }
    }
  }
}

@MainActor
private struct RoutineOrganizingView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    VStack(spacing: 0) {
      Image(AppImage.moruImageHalo)
        .resizable()
        .scaledToFit()
        .frame(width: 200, height: 200)
        .padding(.top, 104)

      Text(OnboardingCopy.organizingTitle)
        .onboardingTextStyle(.h2.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)
        .multilineTextAlignment(.center)
        .padding(.top, MoruPilotSpacing.twelve)

      Text(OnboardingCopy.organizingSubtitle)
        .onboardingTextStyle(.c1)
        .foregroundStyle(MoruPilotColor.textTertiary)
        .padding(.top, MoruPilotSpacing.twelve)

      VStack(alignment: .leading, spacing: MoruPilotSpacing.sixteen) {
        OnboardingChecklistRow(title: "루틴 항목 파악", isDone: true)
        OnboardingChecklistRow(title: "유형 분류", isDone: true)
        OnboardingChecklistRow(title: "시간 배분 중", isDone: false)
      }
      .padding(.top, AppSpacing.fortyEight)

      Spacer(minLength: MoruPilotSpacing.twenty)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, MoruPilotSpacing.twenty)
    .task {
      do {
        try await Task.sleep(for: .seconds(1))
      } catch {
        return
      }

      guard !Task.isCancelled else {
        return
      }

      await MainActor.run {
        viewModel.organizingDidFinish()
      }
    }
  }
}

private struct RoutineReviewView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    OnboardingStepLayout(
      title: OnboardingCopy.reviewTitle,
      subtitle: "",
      titleSpacing: AppSpacing.forty
    ) {
      if let routine = viewModel.validatedPreviewRoutine {
        if viewModel.allowsReviewEditing {
          EditableRoutineReviewForm(
            viewModel: viewModel,
            routine: routine,
            alarmSummary: "\(weekdaySummary) · \(viewModel.draft.formattedKoreanAlarmTime)"
          )
        } else {
          RoutineReviewForm(
            routine: routine,
            alarmSummary: "\(weekdaySummary) · \(viewModel.draft.formattedKoreanAlarmTime)"
          )
        }
      } else {
        PreviewUnavailableState(errorMessage: viewModel.errorMessage)
      }
    }
  }

  private var weekdaySummary: String {
    viewModel.draft.orderedWeekdays
      .map(\.shortKoreanTitle)
      .joined(separator: " ")
  }
}

private struct OnboardingAlarmSettingView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    OnboardingStepLayout(
      title: "아침에 일어날\n시간을 설정해 주세요",
      subtitle: "",
      titleSpacing: AppSpacing.fortyEight
    ) {
      if viewModel.validatedPreviewRoutine != nil {
        VStack(spacing: MoruPilotSpacing.twenty) {
          Text("기상 시간")
            .onboardingTextStyle(.b4.weight(.semiBold))
            .foregroundStyle(MoruPilotColor.textSecondary)
            .frame(maxWidth: .infinity)

          TimeWheelControl(viewModel: viewModel)

          Rectangle()
            .fill(MoruPilotColor.accentTint)
            .frame(height: 1)

          Text("반복 요일")
            .onboardingTextStyle(.b4.weight(.semiBold))
            .foregroundStyle(MoruPilotColor.textSecondary)
            .frame(maxWidth: .infinity)

          WeekdayCircleSelector(viewModel: viewModel)
            .frame(maxWidth: .infinity)
        }
      } else {
        PreviewUnavailableState(errorMessage: viewModel.errorMessage)
      }
    }
  }
}

private struct OnboardingVoiceSelectionView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    OnboardingStepLayout(
      title: "어떤 목소리로\n코칭 받을까요?",
      subtitle: OnboardingCopy.voiceSubtitle,
      titleSpacing: AppSpacing.forty
    ) {
      VStack(spacing: MoruPilotSpacing.twelve) {
        ForEach(VoiceProfile.localVoices) { voice in
          MoruVoiceCard(
            name: voice.displayName,
            description: OnboardingCopy.voiceDescription(for: voice),
            isSelected: Binding {
              viewModel.draft.selectedVoice == voice
            } set: { isSelected in
              if isSelected {
                viewModel.selectVoice(voice)
              }
            }
          )
        }
      }
    }
    .onDisappear(perform: viewModel.voiceSelectionViewDidDisappear)
  }
}

private struct OnboardingCompletionView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    VStack(spacing: 0) {
      Image(AppImage.moruRoutineCompleted)
        .resizable()
        .scaledToFit()
        .frame(width: 160, height: 160)

      VStack(spacing: AppSpacing.md) {
        Text("루틴 설정이\n완료되었어요")
          .onboardingTextStyle(.h2.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textStrong)
          .multilineTextAlignment(.center)

        Text("모루와 모닝 루틴 하러\n가볼까요?")
          .onboardingTextStyle(.c1.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textTertiary)
          .multilineTextAlignment(.center)
      }
      .padding(.top, AppSpacing.fortyEight)

      Spacer(minLength: AppSpacing.thirtySix)
    }
    .padding(.top, 132)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

enum OnboardingDuration {
  static func roundedMinutes(for estimatedSeconds: Int?) -> Int {
    let seconds = max(0, estimatedSeconds ?? 60)
    return max(1, (seconds + 59) / 60)
  }

  static func totalMinutes(for routine: Routine) -> Int {
    routine.steps.reduce(0) { total, step in
      total + roundedMinutes(for: step.estimatedSeconds)
    }
  }
}

private struct PreviewUnavailableState: View {
  let errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      Text("루틴 미리보기를 사용할 수 없어요")
        .onboardingTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)

      Text(errorMessage ?? "이전 단계에서 다시 시도해 주세요.")
        .onboardingTextStyle(.c1)
        .foregroundStyle(MoruPilotColor.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MoruPilotSpacing.sixteen)
    .background(OnboardingSurface.card)
    .overlay(
      RoundedRectangle(cornerRadius: MoruPilotRadius.card)
        .stroke(MoruPilotColor.border, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.card))
  }
}

private struct RoutineMetaPill: View {
  let goalTitle: String?
  let stepCount: Int
  let durationMinutes: Int

  var body: some View {
    HStack {
      Text(goalTitle.map { "\($0) 목표" } ?? "맞춤 루틴")
        .onboardingTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textSecondary)

      Spacer()

      Text("\(stepCount)개 / 총 \(durationMinutes)분")
        .onboardingTextStyle(.c2.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textTertiary)
    }
    .frame(minHeight: 28)
  }
}

private struct RoutineStepListCard: View {
  let routine: Routine

  var body: some View {
    VStack(spacing: MoruPilotSpacing.eight) {
      ForEach(Array(orderedSteps.enumerated()), id: \.element.id) { index, step in
        RoutineStepPreviewRow(index: index + 1, step: step)
      }
    }
  }

  private var orderedSteps: [RoutineStep] {
    routine.steps.sorted { $0.order < $1.order }
  }
}

private struct RoutineStepPreviewRow: View {
  let index: Int
  let step: RoutineStep

  var body: some View {
    HStack(spacing: MoruPilotSpacing.twelve) {
      ZStack {
        Circle()
          .fill(MoruPilotColor.accentSurface)
          .frame(width: 20, height: 20)

        Text("\(index)")
          .onboardingTextStyle(.c2.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.accent)
      }

      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text(step.title)
          .onboardingTextStyle(.c1.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)

        Text("\(step.type.displayTitle) - \(step.durationTitle)")
          .onboardingTextStyle(.c2)
          .foregroundStyle(MoruPilotColor.textSecondary)
      }

      Spacer()
    }
    .padding(.horizontal, MoruPilotSpacing.sixteen)
    .frame(minHeight: 62)
    .background(OnboardingSurface.listRow)
    .overlay(
      RoundedRectangle(cornerRadius: MoruPilotRadius.card)
        .stroke(MoruPilotColor.border, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.card))
  }
}

private struct RoutineReviewForm: View {
  let routine: Routine
  let alarmSummary: String

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.twentyEight) {
      RoutineNameFields(routine: routine)

      VStack(alignment: .leading, spacing: AppSpacing.sm) {
        Text("루틴 알림")
          .onboardingTextStyle(.b4.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textSecondary)

        RoundedInfoField(text: alarmSummary)
      }

      RoutineCountSummary(routine: routine)
      RoutineStepListCard(routine: routine)
    }
  }
}

private struct RoutineNameFields: View {
  let routine: Routine

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      Text("루틴 이름")
        .onboardingTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textSecondary)

      RoundedInfoField(text: routine.name)
      RoundedInfoField(
        text: routine.summary.isEmpty ? "설명이 없어요" : routine.summary,
        isPlaceholder: routine.summary.isEmpty
      )
    }
  }
}

private struct RoundedInfoField: View {
  let text: String
  var isPlaceholder: Bool = false

  var body: some View {
    Text(text)
      .onboardingTextStyle(.b4.weight(.semiBold))
      .foregroundStyle(
        isPlaceholder ? MoruPilotColor.textTertiary : MoruPilotColor.textPrimary
      )
      .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
      .padding(.horizontal, AppSpacing.md)
      .background(OnboardingSurface.input)
      .overlay(
        RoundedRectangle(cornerRadius: MoruPilotRadius.card)
          .stroke(MoruPilotColor.border, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.card))
  }
}

private struct RoutineCountSummary: View {
  let routine: Routine

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      Text("루틴 항목")
        .onboardingTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textSecondary)

      Text("\(routine.steps.count)개 - 총 \(OnboardingDuration.totalMinutes(for: routine))분")
        .onboardingTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textPrimary)
    }
  }
}

private struct OnboardingChecklistRow: View {
  let title: String
  let isDone: Bool

  var body: some View {
    HStack(spacing: AppSpacing.xs) {
      Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(
          isDone ? MoruPilotColor.accent : MoruPilotColor.textTertiary
        )

      Text(title)
        .onboardingTextStyle(.c1.weight(.semiBold))
        .foregroundStyle(
          isDone ? MoruPilotColor.textPrimary : MoruPilotColor.textSecondary
        )
    }
  }
}

private struct TimeWheelControl: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    VStack(spacing: AppSpacing.xs) {
      HStack(spacing: AppSpacing.fortyEight) {
        wheelColumn(
          previous: hourText(viewModel.draft.alarmHour - 1),
          current: hourText(viewModel.draft.alarmHour),
          next: hourText(viewModel.draft.alarmHour + 1),
          decrement: {
            viewModel.updateAlarm(
              hour: wrappedHour(viewModel.draft.alarmHour - 1),
              minute: viewModel.draft.alarmMinute
            )
          },
          increment: {
            viewModel.updateAlarm(
              hour: wrappedHour(viewModel.draft.alarmHour + 1),
              minute: viewModel.draft.alarmMinute
            )
          }
        )

        wheelColumn(
          previous: minuteText(viewModel.draft.alarmMinute - 1),
          current: minuteText(viewModel.draft.alarmMinute),
          next: minuteText(viewModel.draft.alarmMinute + 1),
          decrement: {
            viewModel.updateAlarm(
              hour: viewModel.draft.alarmHour,
              minute: wrappedMinute(viewModel.draft.alarmMinute - 1)
            )
          },
          increment: {
            viewModel.updateAlarm(
              hour: viewModel.draft.alarmHour,
              minute: wrappedMinute(viewModel.draft.alarmMinute + 1)
            )
          }
        )
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, AppSpacing.sm)
      .background(
        RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard)
          .fill(MoruPilotColor.progressTrack)
          .frame(height: 44)
      )
    }
  }

  private func wheelColumn(
    previous: String,
    current: String,
    next: String,
    decrement: @escaping () -> Void,
    increment: @escaping () -> Void
  ) -> some View {
    VStack(spacing: AppSpacing.xs) {
      Button(action: decrement) {
        Text(previous)
          .onboardingTextStyle(.b2.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textTertiary)
          .frame(width: 64, height: 36)
      }
      .buttonStyle(.plain)

      Text(current)
        .onboardingTextStyle(.h2.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)
        .frame(width: 64, height: 44)

      Button(action: increment) {
        Text(next)
          .onboardingTextStyle(.b2.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textTertiary)
          .frame(width: 64, height: 36)
      }
      .buttonStyle(.plain)
    }
  }

  private func hourText(_ value: Int) -> String {
    String(format: "%02d", wrappedHour(value))
  }

  private func minuteText(_ value: Int) -> String {
    String(format: "%02d", wrappedMinute(value))
  }

  private func wrappedHour(_ value: Int) -> Int {
    (value % 24 + 24) % 24
  }

  private func wrappedMinute(_ value: Int) -> Int {
    (value % 60 + 60) % 60
  }
}

private struct WeekdayCircleSelector: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    HStack(spacing: AppSpacing.xs) {
      ForEach(Weekday.onboardingDisplayOrder) { weekday in
        Button {
          viewModel.toggleWeekday(weekday)
        } label: {
          Text(weekday.shortKoreanTitle)
            .onboardingTextStyle(.b4.weight(.semiBold))
            .foregroundStyle(
              viewModel.draft.selectedWeekdays.contains(weekday)
                ? AppColor.grayWhite
                : MoruPilotColor.textTertiary
            )
            .minimumScaleFactor(0.7)
            .frame(width: 42, height: 42)
            .background(
              viewModel.draft.selectedWeekdays.contains(weekday)
                ? MoruPilotColor.accent
                : MoruPilotColor.progressTrack
            )
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }
    }
  }
}

private struct OnboardingOptionButton: View {
  let title: String
  let subtitle: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: AppSpacing.md) {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
          Text(title)
            .onboardingTextStyle(.b2.weight(.semiBold))
            .foregroundStyle(MoruPilotColor.textStrong)

          Text(subtitle)
            .onboardingTextStyle(.c1.weight(.semiBold))
            .foregroundStyle(MoruPilotColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 20, weight: .medium))
          .foregroundStyle(MoruPilotColor.textSecondary)
      }
      .padding(.horizontal, MoruPilotSpacing.twenty)
      .frame(maxWidth: .infinity, minHeight: 84)
      .background(OnboardingSurface.card)
      .overlay(
        RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard)
          .stroke(
            isSelected ? MoruPilotColor.accent : MoruPilotColor.border,
            lineWidth: 1.5
          )
      )
      .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard))
    }
    .buttonStyle(.plain)
  }
}

private struct FlowLayout<Content: View>: View {
  let spacing: CGFloat
  @ViewBuilder var content: Content

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: spacing) {
        content
      }

      VStack(alignment: .leading, spacing: spacing) {
        content
      }
    }
  }
}

private extension OnboardingStep {
  var showsFooter: Bool {
    switch self {
    case .experience, .organizing:
      return false
    case .goals, .suggestedRoutine, .duration, .freeform, .review, .alarm, .voice, .completion:
      return true
    }
  }
}

private extension OnboardingDraft {
  var primaryGoalTitle: String? {
    guard let firstGoalTag = orderedGoalTags.first,
          let option = Self.goalOptions.first(where: { $0.tag == firstGoalTag }) else {
      return nil
    }

    return option.title
  }

  var formattedKoreanAlarmTime: String {
    let period = alarmHour < 12 ? "오전" : "오후"
    let displayHour = alarmHour % 12 == 0 ? 12 : alarmHour % 12
    return String(format: "%@ %d:%02d", period, displayHour, alarmMinute)
  }
}

private extension OnboardingGoalOption {
  var icon: MoruSelectionCardIcon {
    switch tag {
    case "health":
      return .health
    case "mind":
      return .mind
    case "habit":
      return .habit
    default:
      return .energy
    }
  }
}

private extension RoutineExperience {
  var title: String {
    switch self {
    case .firstTime:
      return "처음이에요"
    case .wantsRecommendation:
      return "추천 받고 싶어요"
    case .hasRoutine:
      return "루틴 있어요"
    }
  }

}

private extension RoutineStepType {
  var displayTitle: String {
    switch self {
    case .confirm:
      return "확인형"
    case .timer:
      return "타이머형"
    case .input:
      return "입력형"
    }
  }
}

private extension RoutineStep {
  var durationTitle: String {
    "\(OnboardingDuration.roundedMinutes(for: estimatedSeconds))분"
  }
}

private struct OnboardingTextStyleModifier: ViewModifier {
  let style: MoruTextStyle
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @ViewBuilder
  func body(content: Content) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      content.font(
        .custom(
          style.weight.rawValue,
          size: style.fontSize,
          relativeTo: style.relativeTextStyle
        )
      )
    } else {
      content.moruTextStyle(style)
    }
  }
}

private extension View {
  func onboardingTextStyle(_ style: MoruTextStyle) -> some View {
    modifier(OnboardingTextStyleModifier(style: style))
  }
}

#if DEBUG
#Preview {
  OnboardingFlowView(
    viewModel: OnboardingViewModel(
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      completeOnboardingUseCase: PreviewCompleteOnboardingUseCase(),
      onCompleted: { _ in }
    )
  )
}

private final class PreviewCompleteOnboardingUseCase: CompleteOnboardingUseCaseProtocol {
  func execute(
    _ request: CompleteOnboardingRequest
  ) async throws -> CompleteOnboardingResult {
    CompleteOnboardingResult(
      profile: LocalProfile(selectedVoice: request.selectedVoice),
      routine: try LocalTemplateSuggestionService.shared.makeRoutine(from: request.suggestionInput)
    )
  }
}
#endif
