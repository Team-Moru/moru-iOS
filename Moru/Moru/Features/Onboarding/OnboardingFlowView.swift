//
//  OnboardingFlowView.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import AVFAudio
import MediaPlayer
import SwiftUI

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
        MoruProgressBar(
          current: progressIndex,
          total: viewModel.progressTotal,
          componentStyle: .figmaPilot
        )
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

private enum OnboardingSurface {
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
        VStack(spacing: AppSpacing.lg) {
          RoutineSuggestionSourceNotice(
            source: viewModel.draft.suggestionSource
          )

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
    TimelineView(
      .animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)
    ) { context in
      let time = reduceMotion
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
          RoutineSuggestionSourceNotice(
            source: viewModel.draft.suggestionSource
          )

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

          VStack(alignment: .leading, spacing: MoruPilotSpacing.twelve) {
            Text("알람")
              .onboardingTextStyle(.b4.weight(.semiBold))
              .foregroundStyle(MoruPilotColor.textSecondary)

            OnboardingAlarmOptionsCard(viewModel: viewModel)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(
            .top,
            dynamicTypeSize.isAccessibilitySize
              ? -MoruPilotSpacing.twelve
              : -MoruPilotSpacing.twenty
          )
        }
      } else {
        PreviewUnavailableState(errorMessage: viewModel.errorMessage)
      }
    }
  }
}

private struct OnboardingAlarmOptionsCard: View {
  @ObservedObject var viewModel: OnboardingViewModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: cardSpacing) {
      soundHeader
      systemVolumeControl
      settingRow(
        title: "날씨 알려주기",
        isOn: Binding(
          get: { viewModel.draft.includeWeather },
          set: { isOn in
            viewModel.setIncludeWeather(isOn)
          }
        )
      )
      settingRow(
        title: "오늘의 운세 알려주기",
        isOn: Binding(
          get: { viewModel.draft.includeFortune },
          set: { isOn in
            viewModel.setIncludeFortune(isOn)
          }
        )
      )
    }
    .padding(.horizontal, horizontalCardPadding)
    .padding(.vertical, verticalCardPadding)
    .background(OnboardingSurface.card)
    .overlay(
      RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard)
        .stroke(MoruPilotColor.border, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard))
    .shadow(
      color: MoruPilotColor.shadow.opacity(0.45),
      radius: 8,
      x: 0,
      y: 4
    )
    .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 0 : 5)
    .accessibilityHint(OnboardingCopy.alarmSoundGuidance)
  }

  private var cardSpacing: CGFloat {
    dynamicTypeSize.isAccessibilitySize
      ? MoruPilotSpacing.sixteen
      : MoruPilotSpacing.four
  }

  private var horizontalCardPadding: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? MoruPilotSpacing.twenty : AppSpacing.xl
  }

  private var verticalCardPadding: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? MoruPilotSpacing.twenty : MoruPilotSpacing.twelve
  }

  @ViewBuilder
  private var soundHeader: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
        HStack(spacing: MoruPilotSpacing.twelve) {
          soundTitle
          Spacer(minLength: MoruPilotSpacing.eight)
          alarmSoundName
        }

        Text("다음")
          .onboardingTextStyle(.b4.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textStrong)
          .frame(maxWidth: .infinity)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      ZStack {
        HStack(spacing: MoruPilotSpacing.twelve) {
          soundTitle
          Spacer(minLength: MoruPilotSpacing.eight)
          alarmSoundName
        }

        Text("다음")
          .onboardingTextStyle(.b4.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textStrong)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private var soundTitle: some View {
    Text("사운드")
      .onboardingTextStyle(.b4.weight(.semiBold))
      .foregroundStyle(MoruPilotColor.textSecondary)
  }

  private var alarmSoundName: some View {
    Text("\(OnboardingCopy.alarmSoundName) >")
      .onboardingTextStyle(.b4.weight(.semiBold))
      .foregroundStyle(MoruPilotColor.textSecondary)
      .lineLimit(1)
  }

  private var systemVolumeControl: some View {
    HStack(spacing: MoruPilotSpacing.eight) {
      Image(systemName: "speaker.wave.1")
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(MoruPilotColor.accent)
        .frame(width: 26, height: 28)
        .accessibilityHidden(true)

      OnboardingSystemVolumeSlider()
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .accessibilityLabel("알람 음량")
        .accessibilityHint("좌우로 조절해 기기 음량을 변경합니다.")
    }
  }

  private func settingRow(
    title: String,
    isOn: Binding<Bool>
  ) -> some View {
    HStack(spacing: MoruPilotSpacing.twelve) {
      Text(title)
        .onboardingTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: MoruPilotSpacing.eight)

      Button {
        isOn.wrappedValue.toggle()
      } label: {
        ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
          Capsule()
            .fill(
              isOn.wrappedValue
                ? MoruPilotColor.accent
                : MoruPilotColor.border
            )

          Circle()
            .fill(Color.white)
            .frame(width: 20, height: 20)
            .padding(.horizontal, 2)
        }
        .frame(width: 42, height: 24)
      }
      .buttonStyle(.plain)
      .frame(minWidth: 44, minHeight: 31)
    }
    .frame(maxWidth: .infinity, minHeight: 31)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(title)
    .accessibilityValue(isOn.wrappedValue ? "켬" : "끔")
  }
}

struct OnboardingSystemVolumeSlider: UIViewRepresentable {
  func makeUIView(context: Context) -> OnboardingSystemVolumeControlView {
    OnboardingSystemVolumeControlView(frame: .zero)
  }

  func updateUIView(
    _ volumeView: OnboardingSystemVolumeControlView,
    context: Context
  ) {
    volumeView.refreshFromSystemVolume()
  }
}

final class OnboardingSystemVolumeControlView: UIView {
  let slider = UISlider(frame: .zero)
  private let systemVolumeView = MPVolumeView(frame: .zero)

  override init(frame: CGRect) {
    super.init(frame: frame)
    configureView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    systemVolumeView.frame = CGRect(x: -2, y: -2, width: 1, height: 1)
    refreshFromSystemVolume()
  }

  func refreshFromSystemVolume() {
    guard !slider.isTracking else {
      return
    }

    slider.value = AVAudioSession.sharedInstance().outputVolume
  }

  func setVolumeForTesting(_ value: Float) {
    slider.value = value
    applySliderValue(slider)
  }

  private func configureView() {
    clipsToBounds = true

    slider.translatesAutoresizingMaskIntoConstraints = false
    slider.isEnabled = true
    slider.isContinuous = true
    slider.minimumValue = 0
    slider.maximumValue = 1
    slider.minimumTrackTintColor = UIColor(MoruPilotColor.accent)
    slider.maximumTrackTintColor = UIColor(MoruPilotColor.accentTint)
    slider.thumbTintColor = UIColor(MoruPilotColor.accent)
    let thumbConfiguration = UIImage.SymbolConfiguration(
      pointSize: 18,
      weight: .regular
    )
    let thumbImage = UIImage(
      systemName: "circle.fill",
      withConfiguration: thumbConfiguration
    )?.withTintColor(
      UIColor(MoruPilotColor.accent),
      renderingMode: .alwaysOriginal
    )
    slider.setThumbImage(thumbImage, for: .normal)
    slider.setThumbImage(thumbImage, for: .highlighted)
    slider.value = AVAudioSession.sharedInstance().outputVolume
    slider.addTarget(self, action: #selector(applySliderValue), for: .valueChanged)

    systemVolumeView.showsVolumeSlider = true
    systemVolumeView.isUserInteractionEnabled = false
    systemVolumeView.alpha = 0.01

    addSubview(systemVolumeView)
    addSubview(slider)
    NSLayoutConstraint.activate([
      slider.leadingAnchor.constraint(equalTo: leadingAnchor),
      slider.trailingAnchor.constraint(equalTo: trailingAnchor),
      slider.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  @objc
  private func applySliderValue(_ sender: UISlider) {
    systemVolumeView.layoutIfNeeded()
    guard let systemSlider = findSlider(in: systemVolumeView) else {
      return
    }

    systemSlider.setValue(sender.value, animated: false)
    systemSlider.sendActions(for: .valueChanged)
  }

  private func findSlider(in view: UIView) -> UISlider? {
    if let slider = view as? UISlider {
      return slider
    }

    for subview in view.subviews {
      if let slider = findSlider(in: subview) {
        return slider
      }
    }

    return nil
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
    routine.steps.reduce(0) { total, step in
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

private struct RoutineSuggestionSourceNotice: View {
  let source: RoutineSuggestionSource?

  var body: some View {
    if let source {
      VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
        Text(source.displayTitle)
          .onboardingTextStyle(.c1.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textPrimary)

        Text(source.displayMessage)
          .onboardingTextStyle(.c2)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(MoruPilotSpacing.twelve)
      .background(MoruPilotColor.accentSurface)
      .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.card))
      .accessibilityIdentifier("routine.suggestion.source")
    }
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
          ? "시간 선택기를 닫습니다. 위아래로 쓸어 5분 단위로 조절할 수 있습니다."
          : "시간 선택기를 엽니다. 위아래로 쓸어 5분 단위로 조절할 수 있습니다."
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
    HStack(spacing: MoruPilotSpacing.twelve) {
      wheelColumn(
        label: "시간",
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

      Text(":")
        .font(
          .custom(
            MoruTextWeight.semiBold.rawValue,
            fixedSize: 30
          )
        )
        .foregroundStyle(MoruPilotColor.textStrong)
        .accessibilityHidden(true)

      wheelColumn(
        label: "분",
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
    .padding(.horizontal, MoruPilotSpacing.twenty)
    .padding(.vertical, MoruPilotSpacing.twelve)
    .background(OnboardingSurface.card.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard))
  }

  private func wheelColumn(
    label: String,
    previous: String,
    current: String,
    next: String,
    decrement: @escaping () -> Void,
    increment: @escaping () -> Void
  ) -> some View {
    VStack(spacing: AppSpacing.xs) {
      Button(action: decrement) {
        Text(previous)
          .font(
            .custom(
              MoruTextWeight.semiBold.rawValue,
              fixedSize: 18
            )
          )
          .foregroundStyle(MoruPilotColor.textTertiary)
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(label) 줄이기")

      Text(current)
        .font(
          .custom(
            MoruTextWeight.semiBold.rawValue,
            fixedSize: 30
          )
        )
        .foregroundStyle(MoruPilotColor.textStrong)
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityHidden(true)

      Button(action: increment) {
        Text(next)
          .font(
            .custom(
              MoruTextWeight.semiBold.rawValue,
              fixedSize: 18
            )
          )
          .foregroundStyle(MoruPilotColor.textTertiary)
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(label) 늘리기")
    }
    .frame(maxWidth: .infinity)
  }

  private func hourText(_ value: Int) -> String {
    OnboardingAlarmTimePresentation.displayHourText(for: value)
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
