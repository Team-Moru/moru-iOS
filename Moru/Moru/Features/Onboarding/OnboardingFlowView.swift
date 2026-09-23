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

  @State private var viewModel: OnboardingViewModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(viewModel: OnboardingViewModel) {
    _viewModel = State(initialValue: viewModel)
  }

  var body: some View {
    NavigationStack {
      Group {
        if viewModel.step == .completion || viewModel.step == .organizing {
          stepContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollView(showsIndicators: false) {
            stepContent
              .padding(.horizontal, MoruSpacing.gutter)
              .padding(.top, MoruSpacing.thirtyTwo)
              .padding(.bottom, contentBottomSpacing)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .defaultScrollAnchor(.top)
          .accessibilityIdentifier("onboarding.scroll.content")
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .safeAreaBar(edge: .bottom) {
        if viewModel.step.showsFooter {
          OnboardingFooterView(viewModel: viewModel)
        }
      }
      .background(OnboardingBackgroundView())
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if viewModel.canNavigateBack {
          ToolbarItem(placement: .cancellationAction) {
            Button(action: viewModel.backButtonDidTap) {
              Image(systemName: "chevron.left")
            }
            .disabled(viewModel.isSaving)
            .accessibilityLabel("이전 단계로 돌아가기")
            .accessibilityIdentifier("onboarding.back")
          }
        }
        if let progressIndex = viewModel.progressIndex {
          ToolbarItem(placement: .principal) {
            OnboardingProgressHeader(
              current: progressIndex,
              total: viewModel.progressTotal
            )
          }
        }
        if viewModel.canCancel {
          ToolbarItem(placement: .confirmationAction) {
            Button("취소", action: viewModel.cancelButtonDidTap)
              .accessibilityIdentifier(
                OnboardingFlowView.cancelAccessibilityIdentifier
              )
          }
        }
      }
      .toolbar(
        viewModel.progressIndex != nil || viewModel.canCancel ? .automatic : .hidden,
        for: .navigationBar
      )
    }
    .accessibilityIdentifier(
      viewModel.flowMode == .recommendedAddition
        ? Self.recommendedRootAccessibilityIdentifier
        : ""
    )
    .alert(
      "다른 루틴을 끌까요?",
      isPresented: Binding(
        get: { viewModel.activeRoutineConflict != nil },
        set: { isPresented in
          if !isPresented {
            viewModel.keepExistingActiveRoutineButtonDidTap()
          }
        }
      ),
      presenting: viewModel.activeRoutineConflict
    ) { _ in
      Button("취소", role: .cancel, action: viewModel.keepExistingActiveRoutineButtonDidTap)
      Button("변경하기", action: viewModel.replaceActiveRoutineButtonDidTap)
    } message: { conflict in
      Text(RoutineManagementCopy.activeRoutineReplacementMessage(conflict))
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

}

/// 툴바 principal에 얹는 진행바. 제목 대신 위젯을 넣는 경우라 navigationTitle을 쓰지 않는다.
private struct OnboardingProgressHeader: View {
  let current: Int
  let total: Int

  var body: some View {
    HStack(spacing: MoruSpacing.twelve) {
      MoruProgressBar(
        current: current,
        total: total,
        showsLabel: false
      )
      .frame(width: 160)

      Text("\(current)/\(total)")
        .moruTextStyle(.c2)
        .foregroundStyle(MoruColor.textPrimary)
        .fixedSize()
    }
  }
}

private struct OnboardingFooterView: View {
  let viewModel: OnboardingViewModel

  var body: some View {
    VStack(spacing: MoruSpacing.eight) {
      if let errorMessage = viewModel.errorMessage {
        Text(errorMessage)
          .moruTextStyle(.c2)
          .foregroundStyle(AppColor.coral300)
          .multilineTextAlignment(.center)
      } else if let blockedReason = viewModel.advanceBlockedReason {
        Text(blockedReason)
          .moruTextStyle(.c2)
          .foregroundStyle(MoruColor.textTertiary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }

      MoruButton(
        viewModel.primaryButtonTitle,
        isEnabled: viewModel.canAdvance,
        isLoading: viewModel.isSaving || viewModel.isSuggesting
      ) {
        viewModel.primaryButtonDidTap()
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, MoruSpacing.twenty)
    .padding(.top, MoruSpacing.sixteen)
    .padding(.bottom, viewModel.step == .completion ? 0 : MoruSpacing.eight)
  }
}

private struct OnboardingBackgroundView: View {
  var body: some View {
    LinearGradient(
      colors: [
        AppColor.grayWhite,
        MoruColor.canvas,
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
          .moruTextStyle(.h2.weight(.semiBold))
          .foregroundStyle(MoruColor.textStrong)
          .fixedSize(horizontal: false, vertical: true)

        if !subtitle.isEmpty {
          Text(subtitle)
            .moruTextStyle(.c1)
            .foregroundStyle(MoruColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct RoutineExperienceQuestionView: View {
  let viewModel: OnboardingViewModel

  var body: some View {
    OnboardingStepLayout(
      title: "루틴 경험이\n있으신가요?",
      subtitle: OnboardingCopy.experienceSubtitle,
      titleSpacing: 68
    ) {
      VStack(spacing: MoruSpacing.twelve) {
        ForEach(RoutineExperience.allCases) { experience in
          OnboardingOptionButton(
            title: experience.title,
            subtitle: OnboardingCopy.experienceDescription(for: experience),
            isSelected: viewModel.draft.didChooseExperience
              && viewModel.draft.experience == experience
          ) {
            viewModel.selectExperience(experience)
          }
        }
      }
    }
  }
}

private struct RoutineGoalSelectionView: View {
  let viewModel: OnboardingViewModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    OnboardingStepLayout(
      title: "어떤 목표로\n시작할까요?",
      subtitle: "",
      titleSpacing: OnboardingFigmaLayout.goalTitleContentSpacing
    ) {
      LazyVGrid(columns: columns, spacing: MoruSpacing.twelve) {
        ForEach(OnboardingDraft.goalOptions) { option in
          Button {
            viewModel.toggleGoal(tag: option.tag)
          } label: {
            HStack(spacing: MoruSpacing.twelve) {
              MoruSelectionIcon(icon: option.icon)
                .frame(width: 32, height: 32)

              VStack(alignment: .leading, spacing: MoruSpacing.four) {
                Text(option.title)
                  .moruTextStyle(.b2.weight(.semiBold))
                  .foregroundStyle(MoruColor.textStrong)
                  .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                  .minimumScaleFactor(0.8)

                Text(option.subtitle)
                  .moruTextStyle(.c1.weight(.semiBold))
                  .foregroundStyle(MoruColor.textSecondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .frame(
              maxWidth: .infinity,
              minHeight: dynamicTypeSize.isAccessibilitySize ? 132 : 104,
              alignment: .leading
            )
            .padding(.horizontal, MoruSpacing.sixteen)
            .background(OnboardingSurface.card)
            .overlay(
              RoundedRectangle(cornerRadius: MoruRadius.largeCard)
                .stroke(
                  viewModel.draft.selectedGoalTags.contains(option.tag)
                    ? MoruColor.accent
                    : MoruColor.border,
                  lineWidth: 1.5
                )
            )
            .clipShape(
              RoundedRectangle(cornerRadius: MoruRadius.largeCard)
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
      GridItem(.flexible(), spacing: MoruSpacing.twelve),
      GridItem(.flexible()),
    ]
  }
}

private struct SuggestedRoutinePreviewView: View {
  let viewModel: OnboardingViewModel

  var body: some View {
    OnboardingStepLayout(
      // 이 초안은 선택한 목표에 맞춘 로컬 템플릿이다. 입력한 문장을 분석해
      // 만든 것이 아니므로 "나만의"라고 말하지 않는다.
      title: "이렇게 시작해\n볼까요?",
      subtitle: OnboardingCopy.suggestedRoutineSubtitle,
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
  let viewModel: OnboardingViewModel

  var body: some View {
    if let routine = viewModel.validatedPreviewRoutine {
      let totalMinutes = OnboardingDuration.totalMinutes(for: routine)

      VStack(alignment: .leading, spacing: AppSpacing.xl) {
        Text(
          "예상 루틴 시간은\n\(Text("\(totalMinutes)분").foregroundColor(MoruColor.accent))이에요"
        )
        .moruTextStyle(.h2.weight(.semiBold))
        .foregroundColor(MoruColor.textStrong)
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
          MoruColor.accent.opacity(0.42),
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
        .shadow(color: MoruColor.shadow.opacity(0.34), radius: 14)

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
        .fill(MoruColor.accentSoft)
        .frame(width: 16, height: 16)
        .shadow(color: MoruColor.accent.opacity(0.38), radius: 4)
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

nonisolated private struct ClockDurationSector: Shape {
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
  let viewModel: OnboardingViewModel

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
              .moruTextStyle(.c1)
              .foregroundStyle(MoruColor.textTertiary)
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
            .foregroundStyle(MoruColor.textPrimary)
            .frame(minHeight: 200)
            .padding(AppSpacing.sm)
            .scrollContentBackground(.hidden)
            .background(Color.clear)

          Text(
            "\(viewModel.freeformText.count)/"
              + "\(OnboardingViewModel.freeformTextCharacterLimit)"
          )
            .moruTextStyle(.c2)
            .foregroundStyle(MoruColor.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(AppSpacing.md)
            .allowsHitTesting(false)
        }
        .background(OnboardingSurface.input)
        .overlay(
          RoundedRectangle(cornerRadius: MoruRadius.card)
            .stroke(MoruColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: MoruRadius.card))

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
          .moruTextStyle(.c2.weight(.regular))
          .foregroundStyle(MoruColor.textTertiary)
      }
    }
  }
}

@MainActor
private struct RoutineOrganizingView: View {
  let viewModel: OnboardingViewModel

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
        .moruTextStyle(.h2.weight(.semiBold))
        .foregroundStyle(MoruColor.textStrong)
        .multilineTextAlignment(.center)
        .padding(.top, MoruSpacing.twelve)

      Text(OnboardingCopy.organizingSubtitle)
        .moruTextStyle(.c1)
        .foregroundStyle(MoruColor.textTertiary)
        .padding(.top, MoruSpacing.twelve)

      RoutineOrganizingChecklist(progress: progress)
        .padding(.top, AppSpacing.fortyEight)

      Spacer(minLength: MoruSpacing.twenty)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, MoruSpacing.gutter)
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
    VStack(alignment: .leading, spacing: MoruSpacing.sixteen) {
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
      MoruColor.accentTint,
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
  let viewModel: OnboardingViewModel

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
              routine: routine
            )
          } else {
            RoutineReviewForm(
              viewModel: viewModel,
              routine: routine
            )
          }
        }
      } else {
        PreviewUnavailableState(errorMessage: viewModel.errorMessage)
      }
    }
  }
}

private struct OnboardingAlarmSettingView: View {
  /// 요일 선택기에 쓰기 바인딩을 넘겨야 해서 이 화면만 @Bindable을 쓴다.
  @Bindable var viewModel: OnboardingViewModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    OnboardingStepLayout(
      title: "아침에 일어날\n시간을 설정해 주세요",
      subtitle: "",
      titleSpacing: dynamicTypeSize.isAccessibilitySize
        ? MoruSpacing.thirtyTwo
        : OnboardingFigmaLayout.alarmTitleContentSpacing
    ) {
      if viewModel.validatedPreviewRoutine != nil {
        VStack(
          spacing: dynamicTypeSize.isAccessibilitySize
            ? MoruSpacing.twelve
            : MoruSpacing.twenty
        ) {
          Text("기상 시간")
            .moruTextStyle(.b4.weight(.semiBold))
            .foregroundStyle(MoruColor.textSecondary)
            .frame(maxWidth: .infinity)

          TimeWheelControl(viewModel: viewModel)

          Rectangle()
            .fill(MoruColor.accentTint)
            .frame(height: 1)

          Text("반복 요일")
            .moruTextStyle(.b4.weight(.semiBold))
            .foregroundStyle(MoruColor.textSecondary)
            .frame(maxWidth: .infinity)

          MoruWeekdaySelector(selectedWeekdays: $viewModel.draft.selectedWeekdays)
            .frame(maxWidth: .infinity)

          Text(OnboardingCopy.alarmSoundGuidance)
            .moruTextStyle(.c1)
            .foregroundStyle(MoruColor.textTertiary)
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
  let viewModel: OnboardingViewModel

  var body: some View {
    OnboardingStepLayout(
      title: "어떤 목소리로\n코칭 받을까요?",
      subtitle: OnboardingCopy.voiceSubtitle,
      titleSpacing: AppSpacing.forty
    ) {
      VStack(spacing: MoruSpacing.twelve) {
        ForEach(VoiceProfile.localVoices) { voice in
          MoruVoiceCard(
            name: voice.displayName,
            description: OnboardingCopy.voiceDescription(for: voice),
            isSelected: viewModel.draft.selectedVoice == voice
          ) {
            viewModel.selectVoice(voice)
          }
        }
      }
    }
    .onDisappear(perform: viewModel.voiceSelectionViewDidDisappear)
  }
}

private struct OnboardingCompletionView: View {
  let viewModel: OnboardingViewModel

  var body: some View {
    VStack(spacing: 0) {
      Image(AppImage.moruRoutineCompleted)
        .resizable()
        .scaledToFit()
        .frame(width: 160, height: 160)
        .accessibilityHidden(true)

      VStack(spacing: AppSpacing.md) {
        Text("루틴 설정이\n완료되었어요")
          .moruTextStyle(.h2.weight(.semiBold))
          .foregroundStyle(MoruColor.textStrong)
          .multilineTextAlignment(.center)

        Text("모루와 모닝 루틴 하러\n가볼까요?")
          .moruTextStyle(.c1.weight(.semiBold))
          .foregroundStyle(MoruColor.textTertiary)
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
        .moruTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruColor.textStrong)

      Text(errorMessage ?? "이전 단계에서 다시 시도해 주세요.")
        .moruTextStyle(.c1)
        .foregroundStyle(MoruColor.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MoruSpacing.sixteen)
    .background(OnboardingSurface.card)
    .overlay(
      RoundedRectangle(cornerRadius: MoruRadius.card)
        .stroke(MoruColor.border, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: MoruRadius.card))
  }
}

private struct RoutineMetaPill: View {
  let goalTitle: String?
  let stepCount: Int
  let durationMinutes: Int

  var body: some View {
    HStack {
      Text(goalTitle.map { "\($0) 목표" } ?? "맞춤 루틴")
        .moruTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruColor.textSecondary)

      Spacer()

      Text("\(stepCount)개 / 총 \(durationMinutes)분")
        .moruTextStyle(.c2.weight(.semiBold))
        .foregroundStyle(MoruColor.textTertiary)
    }
    .frame(minHeight: 28)
  }
}

private struct RoutineStepListCard: View {
  let routine: Routine

  var body: some View {
    VStack(spacing: MoruSpacing.eight) {
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
  let viewModel: OnboardingViewModel
  let candidates: [RoutineStep]

  var body: some View {
    VStack(spacing: MoruSpacing.eight) {
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
    HStack(spacing: MoruSpacing.twelve) {
      ZStack {
        Circle()
          .fill(indexCircleColor)
          .frame(width: 20, height: 20)

        Text("\(index)")
          .moruTextStyle(.c2.weight(.semiBold))
          .foregroundStyle(indexTextColor)
      }

      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text(step.title)
          .moruTextStyle(
            showsSelectionControl ? .b3.weight(.semiBold) : .c1.weight(.semiBold)
          )
          .foregroundStyle(
            isSelectableAndExcluded
              ? MoruColor.textTertiary
              : MoruColor.textPrimary
          )
          .lineLimit(1)
          .minimumScaleFactor(0.82)

        Text("\(step.type.displayTitle) - \(step.durationTitle)")
          .moruTextStyle(showsSelectionControl ? .b4 : .c2)
          .foregroundStyle(
            isSelectableAndExcluded
              ? MoruColor.textTertiary
              : MoruColor.textSecondary
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
    .padding(.horizontal, MoruSpacing.sixteen)
    .frame(minHeight: 62)
    .background(
      isSelectableAndExcluded
        ? MoruColor.surfaceMuted
        : OnboardingSurface.listRow
    )
    .overlay(
      RoundedRectangle(cornerRadius: MoruRadius.card)
        .stroke(MoruColor.border, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: MoruRadius.card))
  }

  private var showsSelectionControl: Bool {
    selectionStyle != nil && onSelection != nil
  }

  private var isSelectableAndExcluded: Bool {
    showsSelectionControl && isIncluded == false
  }

  private var indexCircleColor: Color {
    guard showsSelectionControl else {
      return MoruColor.accentSurface
    }

    return isIncluded == true
      ? MoruColor.accentSoft
      : MoruColor.accentTint
  }

  private var indexTextColor: Color {
    guard showsSelectionControl else {
      return MoruColor.accent
    }

    return isIncluded == true
      ? AppColor.grayWhite
      : MoruColor.textTertiary
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
  let viewModel: OnboardingViewModel
  let routine: Routine

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.twentyEight) {
      EditableRoutineIdentityFields(viewModel: viewModel)
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

private struct RoutineCountSummary: View {
  let routine: Routine

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      Text("루틴 항목")
        .moruTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruColor.textSecondary)

      Text("\(routine.steps.count)개 - 총 \(OnboardingDuration.totalMinutes(for: routine))분")
        .moruTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruColor.textPrimary)
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
        .moruTextStyle(.c1.weight(.semiBold))
        .foregroundStyle(
          status == .completed
            ? MoruColor.textPrimary
            : MoruColor.textSecondary
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
        .foregroundStyle(MoruColor.textTertiary)
        .transition(.opacity.combined(with: .scale(scale: 0.72)))
    case .active:
      if reduceMotion {
        Image(systemName: "circle.fill")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MoruColor.accent)
      } else {
        ProgressView()
          .controlSize(.small)
          .tint(MoruColor.accent)
          .transition(.opacity.combined(with: .scale(scale: 0.72)))
      }
    case .completed:
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MoruColor.accent)
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
  let viewModel: OnboardingViewModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var isEditing = true

  var body: some View {
    VStack(spacing: MoruSpacing.sixteen) {
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
            .foregroundStyle(MoruColor.textStrong)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 82)

          Text(timePresentation.period)
            .moruTextStyle(.b2.weight(.semiBold))
            .foregroundStyle(MoruColor.textSecondary)
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
    .padding(.bottom, isEditing ? 0 : MoruSpacing.twenty)
    .animation(.easeInOut(duration: 0.2), value: isEditing)
  }

  private var wheelEditor: some View {
    ZStack {
      RoundedRectangle(cornerRadius: MoruRadius.card)
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
            .moruTextStyle(.b2.weight(.semiBold))
            .foregroundStyle(MoruColor.textStrong)

          Text(subtitle)
            .moruTextStyle(.c1.weight(.semiBold))
            .foregroundStyle(MoruColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 20, weight: .medium))
          .foregroundStyle(MoruColor.textSecondary)
      }
      .padding(.horizontal, MoruSpacing.twenty)
      .frame(maxWidth: .infinity, minHeight: 84)
      .background(OnboardingSurface.card)
      .overlay(
        RoundedRectangle(cornerRadius: MoruRadius.largeCard)
          .stroke(
            isSelected ? MoruColor.accent : MoruColor.border,
            lineWidth: 1.5
          )
      )
      .clipShape(RoundedRectangle(cornerRadius: MoruRadius.largeCard))
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
    case .organizing:
      return false
    case .experience, .goals, .suggestedRoutine, .duration, .freeform, .review,
         .alarm, .voice, .completion:
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
