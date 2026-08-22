//
//  OnboardingFlowView.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import SwiftUI

private struct OnboardingCaptureStaticAnimationsKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var onboardingCaptureStaticAnimations: Bool {
    get { self[OnboardingCaptureStaticAnimationsKey.self] }
    set { self[OnboardingCaptureStaticAnimationsKey.self] = newValue }
  }
}

@MainActor
struct OnboardingFlowView: View {
  static let recommendedRootAccessibilityIdentifier =
    "routine.creation.recommended.flow"
  static let cancelAccessibilityIdentifier =
    "routine.creation.recommended.cancel"

  @StateObject private var viewModel: OnboardingViewModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            .padding(.bottom, contentBottomSpacing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultScrollAnchor(.top)
        .accessibilityIdentifier("onboarding.scroll.content")
      }

    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .safeAreaInset(edge: .bottom, spacing: 0) {
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
    .overlay {
      if let activeRoutineConflict = viewModel.activeRoutineConflict {
        activeRoutineConflictDialogOverlay(activeRoutineConflict)
      }
    }
    .onDisappear(perform: viewModel.viewDidDisappear)
  }

  private var contentBottomSpacing: CGFloat {
    guard viewModel.step == .alarm else {
      return AppSpacing.thirtySix
    }

    return dynamicTypeSize.isAccessibilitySize
      ? OnboardingFigmaLayout.alarmAccessibilityScrollBottomSpacing
      : OnboardingFigmaLayout.alarmScrollBottomSpacing
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

  private func activeRoutineConflictDialogOverlay(
    _ conflict: RoutineActivationConflictState
  ) -> some View {
    ZStack {
      AppColor.grayBlack
        .opacity(0.22)
        .ignoresSafeArea()

      MoruDialog(
        title: "다른 루틴을 끌까요?",
        message: RoutineManagementCopy.activeRoutineReplacementMessage(conflict),
        primaryTitle: "취소",
        secondaryTitle: "변경하기",
        primaryAction: viewModel.keepExistingActiveRoutineButtonDidTap,
        secondaryAction: viewModel.replaceActiveRoutineButtonDidTap
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
        HStack(spacing: 0) {
          backButton

          MoruProgressBar(
            current: progressIndex,
            total: viewModel.progressTotal,
            componentStyle: .figmaPilot,
            showsLabel: false
          )
          .frame(maxWidth: .infinity)

          Text("\(progressIndex)/\(viewModel.progressTotal)")
            .onboardingTextStyle(.c2)
            .foregroundStyle(MoruPilotColor.textPrimary)
            .fixedSize()
            .padding(.leading, MoruPilotSpacing.twelve)
        }
      }
    }
    .padding(.horizontal, MoruPilotSpacing.twenty)
    .padding(.top, MoruPilotSpacing.sixteen)
  }

  @ViewBuilder
  private var backButton: some View {
    if viewModel.canNavigateBack {
      Button(action: viewModel.backButtonDidTap) {
        Image(systemName: "chevron.left")
          .font(.system(size: 24, weight: .regular))
          .foregroundStyle(MoruPilotColor.textSecondary)
          .frame(width: 44, height: 44, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(viewModel.isSaving)
      .accessibilityLabel("이전 단계로 돌아가기")
      .accessibilityIdentifier("onboarding.back")
    } else {
      Color.clear
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
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
          if viewModel.isSaving || viewModel.isSuggesting {
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

enum OnboardingSurface {
  static let card = AppColor.grayWhite
  static let input = AppColor.grayWhite
  static let listRow = AppColor.grayWhite
}

enum OnboardingFigmaLayout {
  static let goalTitleContentSpacing: CGFloat = 88
  static let alarmTitleContentSpacing: CGFloat = 48
  static let alarmTimeFontSize: CGFloat = 72
  static let alarmScrollBottomSpacing: CGFloat = 72
  static let alarmAccessibilityScrollBottomSpacing: CGFloat = 128
  static let weekdayButtonSize: CGFloat = 44
  static let maximumWeekdaySpacing: CGFloat = 7

  static func weekdaySpacing(availableWidth: CGFloat) -> CGFloat {
    let itemCount = CGFloat(Weekday.onboardingDisplayOrder.count)
    let gapCount = max(itemCount - 1, 1)
    let availableSpacing =
      (availableWidth - weekdayButtonSize * itemCount) / gapCount
    return min(maximumWeekdaySpacing, max(0, availableSpacing))
  }
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
      titleSpacing: OnboardingFigmaLayout.goalTitleContentSpacing
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
          .disabled(viewModel.isSuggesting)
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
        let candidateSteps = viewModel.recommendedRoutineStepCandidates
        let displayedSteps = candidateSteps.isEmpty
          ? routine.steps.sorted { $0.order < $1.order }
          : candidateSteps

        VStack(spacing: AppSpacing.lg) {
          RoutineMetaPill(
            goalTitle: viewModel.draft.primaryGoalTitle,
            stepCount: viewModel.previewRoutineStepCount,
            durationMinutes: viewModel.previewRoutineDurationMinutes
          )

          if viewModel.hasRecommendedRoutineStepCandidates {
            RecommendedRoutineStepCandidateList(
              viewModel: viewModel,
              candidates: displayedSteps
            )
          } else {
            RoutineStepListCard(routine: routine)
          }
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
      let totalMinutes = OnboardingDuration.totalMinutes(for: routine)

      VStack(alignment: .leading, spacing: AppSpacing.xl) {
        Text(
          "예상 루틴 시간은\n\(Text("\(totalMinutes)분").foregroundColor(MoruPilotColor.accent))이에요"
        )
        .onboardingTextStyle(.h2.weight(.semiBold))
        .foregroundColor(MoruPilotColor.textStrong)
        .fixedSize(horizontal: false, vertical: true)

        RoutineDurationClockView(totalMinutes: totalMinutes)
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

private struct RoutineDurationClockView: View {
  let totalMinutes: Int

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var displayedProgress: CGFloat = 0

  private var targetProgress: CGFloat {
    CGFloat(OnboardingDuration.clockProgress(forMinutes: totalMinutes))
  }

  var body: some View {
    ZStack {
      Circle()
        .trim(from: 0, to: displayedProgress)
        .stroke(
          MoruPilotColor.accent.opacity(0.42),
          style: StrokeStyle(lineWidth: 28, lineCap: .butt)
        )
        .rotationEffect(.degrees(-90))
        .blur(radius: 9)
        .frame(width: 208, height: 208)

      Circle()
        .fill(
          LinearGradient(
            colors: [
              AppColor.babyBlue100,
              AppColor.babyBlue150.opacity(0.82),
            ],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
          )
        )
        .frame(width: 208, height: 208)
        .shadow(color: MoruPilotColor.shadow.opacity(0.34), radius: 14)

      ClockDurationSector(progress: displayedProgress)
        .fill(AppColor.grayWhite.opacity(0.54))
        .frame(width: 208, height: 208)
        .clipShape(Circle())

      ForEach(0..<12, id: \.self) { index in
        Circle()
          .fill(
            index.isMultiple(of: 3)
              ? AppColor.grayWhite.opacity(0.9)
              : AppColor.babyBlue250.opacity(0.68)
          )
          .frame(width: 10, height: 10)
          .offset(y: -87)
          .rotationEffect(.degrees(Double(index) * 30))
      }

      Capsule()
        .fill(AppColor.grayWhite.opacity(0.8))
        .frame(width: 4, height: 76)
        .offset(y: -38)
        .rotationEffect(.degrees(Double(displayedProgress) * 360))

      Circle()
        .fill(MoruPilotColor.accentSoft)
        .frame(width: 16, height: 16)
        .shadow(color: MoruPilotColor.accent.opacity(0.38), radius: 4)
    }
    .frame(width: 240, height: 240)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("예상 루틴 시간 \(totalMinutes)분")
    .onAppear(perform: updateProgress)
    .onChange(of: totalMinutes) { _, _ in
      updateProgress()
    }
  }

  private func updateProgress() {
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) {
      displayedProgress = targetProgress
    }
  }
}

private struct ClockDurationSector: Shape {
  var progress: CGFloat

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let clampedProgress = min(max(progress, 0), 1)
    guard clampedProgress > 0 else {
      return Path()
    }

    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2
    var path = Path()
    path.move(to: center)
    path.addArc(
      center: center,
      radius: radius,
      startAngle: .degrees(-90),
      endAngle: .degrees(-90 + Double(clampedProgress) * 360),
      clockwise: false
    )
    path.closeSubpath()
    return path
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
          if viewModel.freeformText.isEmpty {
            Text("예) 일어나면 물 마시고, 스트레칭 하고, 일기 쓰고,\n오늘 할 일 미리 확인하기")
              .onboardingTextStyle(.c1)
              .foregroundStyle(MoruPilotColor.textTertiary)
              .padding(AppSpacing.md)
          }

          TextEditor(
            text: Binding(
              get: { viewModel.freeformText },
              set: { text in
                viewModel.updateFreeformText(text)
              }
            )
          )
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

          Text(
            "\(viewModel.freeformText.count)/"
              + "\(OnboardingViewModel.freeformTextCharacterLimit)"
          )
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
    RoutineOrganizingContent(progress: viewModel.organizingProgress)
  }
}

private struct RoutineOrganizingContent: View {
  let progress: RoutineOrganizingPresentationPhase

  var body: some View {
    VStack(spacing: 0) {
      OrganizingRoutineOrbView()
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

      RoutineOrganizingChecklist(progress: progress)
        .padding(.top, AppSpacing.fortyEight)

      Spacer(minLength: MoruPilotSpacing.twenty)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, MoruPilotSpacing.twenty)
  }
}

private struct RoutineOrganizingChecklist: View {
  let progress: RoutineOrganizingPresentationPhase

  private let items = [
    "루틴 구성 준비",
    "추천 결과 정리",
    "확인 화면 준비",
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.sixteen) {
      ForEach(Array(items.enumerated()), id: \.offset) { index, title in
        OnboardingChecklistRow(
          title: title,
          status: status(for: index)
        )
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("루틴 정리 진행 상황")
  }

  private func status(for index: Int) -> OnboardingChecklistStatus {
    if progress == .completed || index < progress.rawValue {
      return .completed
    }
    if index == progress.rawValue {
      return .active
    }
    return .pending
  }
}

private struct OrganizingRoutineOrbView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.onboardingCaptureStaticAnimations)
  private var captureStaticAnimations

  private let waveGradient = AngularGradient(
    colors: [
      AppColor.babyBlue200,
      AppColor.purple350.opacity(0.48),
      MoruPilotColor.accentTint,
      AppColor.babyBlue150,
    ],
    center: .center
  )

  var body: some View {
    let isPaused = reduceMotion || captureStaticAnimations

    TimelineView(
      .animation(minimumInterval: 1.0 / 30.0, paused: isPaused)
    ) { context in
      let time = isPaused
        ? 0
        : context.date.timeIntervalSinceReferenceDate
      let coreBreath = CGFloat(sin(time * 2.35))

      ZStack {
        ripple(time: time, offset: 0)
        ripple(time: time, offset: 0.5)

        Image(AppImage.moruImageHalo)
          .resizable()
          .scaledToFit()
          .scaleEffect(0.96 + 0.075 * coreBreath)
      }
    }
    .accessibilityHidden(true)
  }

  private func ripple(time: Double, offset: Double) -> some View {
    let progress = CGFloat(
      (time / 1.7 + offset).truncatingRemainder(dividingBy: 1)
    )

    return Circle()
      .stroke(waveGradient, lineWidth: 2)
      .frame(width: 154, height: 154)
      .scaleEffect(0.84 + progress * 0.45)
      .opacity((1 - progress) * 0.34)
      .blur(radius: 2 + progress * 4)
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
        VStack(spacing: AppSpacing.md) {
          if viewModel.allowsReviewEditing
            && !viewModel.showsRecommendedRoutineStepEditor {
            EditableRoutineReviewForm(
              viewModel: viewModel,
              routine: routine,
              alarmSummary: "\(weekdaySummary) · \(viewModel.draft.formattedKoreanAlarmTime)"
            )
          } else {
            RoutineReviewForm(
              viewModel: viewModel,
              routine: routine,
              alarmSummary: "\(weekdaySummary) · \(viewModel.draft.formattedKoreanAlarmTime)"
            )
          }
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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    OnboardingStepLayout(
      title: "아침에 일어날\n시간을 설정해 주세요",
      subtitle: "",
      titleSpacing: dynamicTypeSize.isAccessibilitySize
        ? MoruPilotSpacing.thirtyTwo
        : OnboardingFigmaLayout.alarmTitleContentSpacing
    ) {
      if viewModel.validatedPreviewRoutine != nil {
        VStack(
          spacing: dynamicTypeSize.isAccessibilitySize
            ? MoruPilotSpacing.twelve
            : MoruPilotSpacing.twenty
        ) {
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

          Text(OnboardingCopy.alarmSoundGuidance)
            .onboardingTextStyle(.c1)
            .foregroundStyle(MoruPilotColor.textTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityHidden(true)

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
    totalMinutes(for: routine.steps)
  }

  static func totalMinutes(for steps: [RoutineStep]) -> Int {
    steps.reduce(0) { total, step in
      total + roundedMinutes(for: step.estimatedSeconds)
    }
  }

  static func clockProgress(forMinutes totalMinutes: Int) -> Double {
    min(max(Double(totalMinutes) / 60, 0), 1)
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

private struct RecommendedRoutineStepCandidateList: View {
  @ObservedObject var viewModel: OnboardingViewModel
  let candidates: [RoutineStep]

  var body: some View {
    VStack(spacing: MoruPilotSpacing.eight) {
      ForEach(Array(candidates.enumerated()), id: \.element.id) { index, step in
        let isSelected = viewModel.isRecommendedRoutineStepSelected(step)

        RoutineStepPreviewRow(
          index: index + 1,
          step: step,
          isIncluded: isSelected,
          selectionStyle: isSelected ? .minus : .plus,
          isSelectionEnabled: viewModel.canToggleRecommendedRoutineStep(step),
          onSelection: {
            viewModel.toggleRecommendedRoutineStep(step)
          }
        )
      }
    }
  }
}

private struct RoutineStepPreviewRow: View {
  let index: Int
  let step: RoutineStep
  let isIncluded: Bool?
  let selectionStyle: MoruSelectControlStyle?
  let isSelectionEnabled: Bool
  let onSelection: (() -> Void)?

  init(
    index: Int,
    step: RoutineStep,
    isIncluded: Bool? = nil,
    selectionStyle: MoruSelectControlStyle? = nil,
    isSelectionEnabled: Bool = true,
    onSelection: (() -> Void)? = nil
  ) {
    self.index = index
    self.step = step
    self.isIncluded = isIncluded
    self.selectionStyle = selectionStyle
    self.isSelectionEnabled = isSelectionEnabled
    self.onSelection = onSelection
  }

  var body: some View {
    HStack(spacing: MoruPilotSpacing.twelve) {
      ZStack {
        Circle()
          .fill(indexCircleColor)
          .frame(width: 20, height: 20)

        Text("\(index)")
          .onboardingTextStyle(.c2.weight(.semiBold))
          .foregroundStyle(indexTextColor)
      }

      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text(step.title)
          .onboardingTextStyle(
            showsSelectionControl ? .b3.weight(.semiBold) : .c1.weight(.semiBold)
          )
          .foregroundStyle(
            isSelectableAndExcluded
              ? MoruPilotColor.textTertiary
              : MoruPilotColor.textPrimary
          )
          .lineLimit(1)
          .minimumScaleFactor(0.82)

        Text("\(step.type.displayTitle) - \(step.durationTitle)")
          .onboardingTextStyle(showsSelectionControl ? .b4 : .c2)
          .foregroundStyle(
            isSelectableAndExcluded
              ? MoruPilotColor.textTertiary
              : MoruPilotColor.textSecondary
          )
      }

      Spacer()

      if let selectionStyle, let onSelection {
        MoruSelectControl(style: selectionStyle, action: onSelection)
          .disabled(!isSelectionEnabled)
          .opacity(isSelectionEnabled ? 1 : 0.42)
          .accessibilityLabel(selectionAccessibilityLabel)
      }
    }
    .padding(.horizontal, MoruPilotSpacing.sixteen)
    .frame(minHeight: 62)
    .background(
      isSelectableAndExcluded
        ? AppColor.moruSurfaceMuted
        : OnboardingSurface.listRow
    )
    .overlay(
      RoundedRectangle(cornerRadius: MoruPilotRadius.card)
        .stroke(MoruPilotColor.border, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.card))
  }

  private var showsSelectionControl: Bool {
    selectionStyle != nil && onSelection != nil
  }

  private var isSelectableAndExcluded: Bool {
    showsSelectionControl && isIncluded == false
  }

  private var indexCircleColor: Color {
    guard showsSelectionControl else {
      return MoruPilotColor.accentSurface
    }

    return isIncluded == true
      ? MoruPilotColor.accentSoft
      : MoruPilotColor.accentTint
  }

  private var indexTextColor: Color {
    guard showsSelectionControl else {
      return MoruPilotColor.accent
    }

    return isIncluded == true
      ? AppColor.grayWhite
      : MoruPilotColor.textTertiary
  }

  private var selectionAccessibilityLabel: String {
    switch selectionStyle {
    case .plus:
      "\(step.title) 추가"
    case .minus:
      "\(step.title) 삭제"
    case nil:
      step.title
    }
  }
}

private struct RoutineReviewForm: View {
  @ObservedObject var viewModel: OnboardingViewModel
  let routine: Routine
  let alarmSummary: String

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.twentyEight) {
      EditableRoutineIdentityFields(viewModel: viewModel)

      VStack(alignment: .leading, spacing: AppSpacing.sm) {
        Text("루틴 알림")
          .onboardingTextStyle(.b4.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textSecondary)

        RoundedInfoField(text: alarmSummary)
      }

      RoutineCountSummary(routine: routine)
      if viewModel.showsRecommendedRoutineStepEditor {
        RecommendedRoutineStepCandidateList(
          viewModel: viewModel,
          candidates: viewModel.recommendedRoutineStepCandidates
        )
      } else {
        RoutineStepListCard(routine: routine)
      }
    }
  }
}

private struct RoundedInfoField: View {
  let text: String

  var body: some View {
    Text(text)
      .onboardingTextStyle(.b4.weight(.semiBold))
      .foregroundStyle(MoruPilotColor.textPrimary)
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

private enum OnboardingChecklistStatus: Equatable {
  case pending
  case active
  case completed
}

private struct OnboardingChecklistRow: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let title: String
  let status: OnboardingChecklistStatus

  var body: some View {
    HStack(spacing: AppSpacing.xs) {
      statusIcon
        .frame(width: 20, height: 20)

      Text(status == .active ? "\(title) 중" : title)
        .onboardingTextStyle(.c1.weight(.semiBold))
        .foregroundStyle(
          status == .completed
            ? MoruPilotColor.textPrimary
            : MoruPilotColor.textSecondary
        )
        .contentTransition(.opacity)
    }
    .animation(
      reduceMotion
        ? nil
        : .easeInOut(
          duration: RoutineOrganizingPresentationTiming.statusAnimationDuration
        ),
      value: status
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(accessibilityValue)
  }

  @ViewBuilder
  private var statusIcon: some View {
    switch status {
    case .pending:
      Image(systemName: "circle")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MoruPilotColor.textTertiary)
        .transition(.opacity.combined(with: .scale(scale: 0.72)))
    case .active:
      if reduceMotion {
        Image(systemName: "circle.fill")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MoruPilotColor.accent)
      } else {
        ProgressView()
          .controlSize(.small)
          .tint(MoruPilotColor.accent)
          .transition(.opacity.combined(with: .scale(scale: 0.72)))
      }
    case .completed:
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MoruPilotColor.accent)
        .transition(.opacity.combined(with: .scale(scale: 0.55)))
    }
  }

  private var accessibilityValue: String {
    switch status {
    case .pending:
      return "대기 중"
    case .active:
      return "진행 중"
    case .completed:
      return "완료"
    }
  }
}

private struct TimeWheelControl: View {
  @ObservedObject var viewModel: OnboardingViewModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var isEditing = false

  var body: some View {
    VStack(spacing: MoruPilotSpacing.sixteen) {
      Button {
        isEditing.toggle()
      } label: {
        VStack(spacing: 0) {
          Text(timePresentation.time)
            .font(
              .custom(
                MoruTextWeight.semiBold.rawValue,
                fixedSize: OnboardingFigmaLayout.alarmTimeFontSize
              )
            )
            .foregroundStyle(MoruPilotColor.textStrong)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 82)

          Text(timePresentation.period)
            .onboardingTextStyle(.b2.weight(.semiBold))
            .foregroundStyle(MoruPilotColor.textSecondary)
            .frame(minHeight: 24)
        }
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("기상 시간")
      .accessibilityValue(timePresentation.accessibilityValue)
      .accessibilityHint(
        isEditing
          ? "시간 선택기를 닫습니다. 시와 분을 위아래로 쓸어 조절할 수 있습니다."
          : "시간 선택기를 엽니다. 시와 분을 위아래로 쓸어 조절할 수 있습니다."
      )
      .accessibilityIdentifier("onboarding.alarm.time")
      .accessibilityAdjustableAction { direction in
        switch direction {
        case .increment:
          adjustTime(byMinutes: 5)
        case .decrement:
          adjustTime(byMinutes: -5)
        @unknown default:
          break
        }
      }

      if isEditing {
        wheelEditor
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .padding(.bottom, isEditing ? 0 : MoruPilotSpacing.twenty)
    .animation(.easeInOut(duration: 0.2), value: isEditing)
  }

  private var wheelEditor: some View {
    ZStack {
      RoundedRectangle(cornerRadius: MoruPilotRadius.card)
        .fill(AppColor.gray150.opacity(0.65))
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 60 : 48)

      HStack(spacing: 0) {
        TimeWheelPicker(value: alarmHourBinding, range: 24)
        TimeWheelPicker(value: alarmMinuteBinding, range: 60)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: dynamicTypeSize.isAccessibilitySize ? 180 : 144)
  }

  private var alarmHourBinding: Binding<Int> {
    Binding(
      get: { viewModel.draft.alarmHour },
      set: { hour in
        viewModel.updateAlarm(
          hour: hour,
          minute: viewModel.draft.alarmMinute
        )
      }
    )
  }

  private var alarmMinuteBinding: Binding<Int> {
    Binding(
      get: { viewModel.draft.alarmMinute },
      set: { minute in
        viewModel.updateAlarm(
          hour: viewModel.draft.alarmHour,
          minute: minute
        )
      }
    )
  }

  private func adjustTime(byMinutes minuteDelta: Int) {
    let minutesPerDay = 24 * 60
    let currentMinutes = viewModel.draft.alarmHour * 60
      + viewModel.draft.alarmMinute
    let adjustedMinutes = (
      currentMinutes + minuteDelta + minutesPerDay
    ) % minutesPerDay
    viewModel.updateAlarm(
      hour: adjustedMinutes / 60,
      minute: adjustedMinutes % 60
    )
  }

  private var timePresentation: OnboardingAlarmTimePresentation {
    OnboardingAlarmTimePresentation(
      hour: viewModel.draft.alarmHour,
      minute: viewModel.draft.alarmMinute
    )
  }
}

private struct WeekdayCircleSelector: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    GeometryReader { geometry in
      HStack(
        spacing: OnboardingFigmaLayout.weekdaySpacing(
          availableWidth: geometry.size.width
        )
      ) {
        ForEach(Weekday.onboardingDisplayOrder) { weekday in
          Button {
            viewModel.toggleWeekday(weekday)
          } label: {
            Text(weekday.shortKoreanTitle)
              .font(
                .custom(
                  MoruTextWeight.semiBold.rawValue,
                  fixedSize: 18
                )
              )
              .foregroundStyle(
                viewModel.draft.selectedWeekdays.contains(weekday)
                  ? AppColor.grayWhite
                  : MoruPilotColor.textTertiary
              )
              .lineLimit(1)
              .frame(width: 42, height: 42)
              .background(
                viewModel.draft.selectedWeekdays.contains(weekday)
                  ? MoruPilotColor.accent
                  : MoruPilotColor.progressTrack
              )
              .clipShape(Circle())
          }
          .buttonStyle(.plain)
          .frame(
            width: OnboardingFigmaLayout.weekdayButtonSize,
            height: OnboardingFigmaLayout.weekdayButtonSize
          )
          .contentShape(Rectangle())
          .accessibilityLabel("\(weekday.shortKoreanTitle)요일")
          .accessibilityValue(
            viewModel.draft.selectedWeekdays.contains(weekday)
              ? "선택됨"
              : "선택 안 됨"
          )
        }
      }
      .frame(maxWidth: .infinity)
    }
    .frame(height: OnboardingFigmaLayout.weekdayButtonSize)
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

struct FlowLayout: Layout {
  let spacing: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let maximumWidth = finiteWidth(proposal.width)
    let measurement = Self.measure(
      sizes: sizes,
      maximumWidth: maximumWidth,
      spacing: spacing
    )

    return CGSize(
      width: proposal.width.flatMap { $0.isFinite ? $0 : nil }
        ?? measurement.size.width,
      height: measurement.size.height
    )
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let measurement = Self.measure(
      sizes: sizes,
      maximumWidth: max(0, bounds.width),
      spacing: spacing
    )

    for (index, subview) in subviews.enumerated() {
      let size = sizes[index]
      let origin = measurement.origins[index]
      subview.place(
        at: CGPoint(
          x: bounds.minX + origin.x,
          y: bounds.minY + origin.y
        ),
        anchor: .topLeading,
        proposal: ProposedViewSize(width: size.width, height: size.height)
      )
    }
  }

  static func measure(
    sizes: [CGSize],
    maximumWidth: CGFloat,
    spacing: CGFloat
  ) -> FlowLayoutMeasurement {
    guard !sizes.isEmpty else {
      return FlowLayoutMeasurement(origins: [], size: .zero)
    }

    let availableWidth = maximumWidth.isFinite
      ? max(0, maximumWidth)
      : .greatestFiniteMagnitude
    var origins: [CGPoint] = []
    var currentX: CGFloat = 0
    var currentY: CGFloat = 0
    var rowHeight: CGFloat = 0
    var measuredWidth: CGFloat = 0

    for size in sizes {
      if currentX > 0, currentX + size.width > availableWidth {
        currentX = 0
        currentY += rowHeight + spacing
        rowHeight = 0
      }

      origins.append(CGPoint(x: currentX, y: currentY))
      measuredWidth = max(measuredWidth, currentX + size.width)
      rowHeight = max(rowHeight, size.height)
      currentX += size.width + spacing
    }

    return FlowLayoutMeasurement(
      origins: origins,
      size: CGSize(width: measuredWidth, height: currentY + rowHeight)
    )
  }

  private func finiteWidth(_ width: CGFloat?) -> CGFloat {
    guard let width, width.isFinite else {
      return .greatestFiniteMagnitude
    }
    return max(0, width)
  }
}

struct FlowLayoutMeasurement: Equatable {
  let origins: [CGPoint]
  let size: CGSize
}

struct OnboardingAlarmTimePresentation: Equatable {
  let time: String
  let period: String
  let accessibilityValue: String

  init(hour: Int, minute: Int) {
    let normalizedHour = (hour % 24 + 24) % 24
    let normalizedMinute = (minute % 60 + 60) % 60
    let displayHour = normalizedHour % 12 == 0 ? 12 : normalizedHour % 12
    time = String(
      format: "%@:%02d",
      Self.displayHourText(for: normalizedHour),
      normalizedMinute
    )
    period = normalizedHour < 12 ? "AM" : "PM"
    accessibilityValue = String(
      format: "%@ %d시 %d분",
      normalizedHour < 12 ? "오전" : "오후",
      displayHour,
      normalizedMinute
    )
  }

  static func displayHourText(for hour: Int) -> String {
    let normalizedHour = (hour % 24 + 24) % 24
    let displayHour = normalizedHour % 12 == 0 ? 12 : normalizedHour % 12
    return String(format: "%02d", displayHour)
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

struct OnboardingTextStyleModifier: ViewModifier {
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

extension View {
  func onboardingTextStyle(_ style: MoruTextStyle) -> some View {
    modifier(OnboardingTextStyleModifier(style: style))
  }
}

#if DEBUG
#Preview("예상 루틴 시간 · 24분") {
  var draft = OnboardingDraft()
  draft.previewRoutine = Routine(
    name: "프리뷰 루틴",
    steps: [
      RoutineStep(
        type: .timer,
        title: "프리뷰 루틴",
        order: 0,
        estimatedSeconds: 35 * 60
      )
    ]
  )

  return OnboardingFlowView(
    viewModel: OnboardingViewModel(
      draft: draft,
      step: .duration,
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )
  )
}

#Preview("루틴 정리 진행 애니메이션") {
  RoutineOrganizingProgressPreview()
}

#Preview("온보딩 · 알람 시간 휠") {
  var draft = OnboardingDraft()
  draft.alarmHour = 7
  draft.alarmMinute = 30
  draft.previewRoutine = try? LocalTemplateSuggestionService.shared.makeRoutine(
    from: draft.suggestionInput
  )

  return OnboardingFlowView(
    viewModel: OnboardingViewModel(
      draft: draft,
      step: .alarm,
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )
  )
}

@MainActor
private struct RoutineOrganizingProgressPreview: View {
  @State private var progress: RoutineOrganizingPresentationPhase =
    .preparingRoutine

  var body: some View {
    RoutineOrganizingContent(progress: progress)
      .task {
        while !Task.isCancelled {
          for phase in RoutineOrganizingPresentationPhase.allCases {
            withAnimation(.snappy(duration: 0.38)) {
              progress = phase
            }
            try? await _Concurrency.Task<Never, Never>.sleep(
              for: phase == .completed ? .seconds(1.4) : .seconds(1)
            )
          }

          progress = .preparingRoutine
          try? await _Concurrency.Task<Never, Never>.sleep(
            for: .milliseconds(600)
          )
        }
      }
  }
}
#endif
