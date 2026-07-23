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
      OnboardingHeaderView(viewModel: viewModel)

      if viewModel.step == .completion {
        stepContent
          .padding(.horizontal, AppSpacing.screenHorizontal)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          stepContent
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.twentyEight)
            .padding(.bottom, AppSpacing.thirtySix)
        }
      }

      if viewModel.step.showsFooter {
        OnboardingFooterView(viewModel: viewModel)
      }
    }
    .background(OnboardingBackgroundView(step: viewModel.step))
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
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      if viewModel.canCancel {
        HStack {
          Spacer()

          Button("취소", action: viewModel.cancelButtonDidTap)
            .font(AppFont.body1NormalMedium)
            .foregroundStyle(AppColor.moruTextSecondary)
            .accessibilityIdentifier(
              OnboardingFlowView.cancelAccessibilityIdentifier
            )
        }
      }

      if let progressIndex = viewModel.progressIndex {
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule()
              .fill(AppColor.gray200)

            Capsule()
              .fill(AppColor.orange350)
              .frame(
                width: proxy.size.width
                  * CGFloat(progressIndex)
                  / CGFloat(viewModel.progressTotal)
              )
          }
        }
        .frame(height: 6)

        Text("\(progressIndex)/\(viewModel.progressTotal)")
          .font(AppFont.body1NormalSemiBold)
          .foregroundStyle(AppColor.moruTextSecondary)
      }
    }
    .padding(.horizontal, AppSpacing.screenHorizontal)
    .padding(.top, AppSpacing.forty)
    .padding(.bottom, AppSpacing.xs)
  }
}

private struct OnboardingFooterView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    VStack(spacing: AppSpacing.sm) {
      if let errorMessage = viewModel.errorMessage {
        Text(errorMessage)
          .font(AppFont.caption1Medium)
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
            .font(AppFont.body1NormalSemiBold)
        }
        .foregroundStyle(AppColor.grayWhite)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(viewModel.canAdvance ? AppColor.orange350 : AppColor.moruDisabled)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
      }
      .buttonStyle(.plain)
      .disabled(!viewModel.canAdvance)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, AppSpacing.bottomCTAHorizontal)
    .padding(.top, AppSpacing.bottomCTAVertical)
    .padding(.bottom, viewModel.step == .completion ? AppSpacing.thirtySix : AppSpacing.md)
    .background(Color.clear)
  }
}

private struct OnboardingBackgroundView: View {
  let step: OnboardingStep

  var body: some View {
    ZStack {
      LinearGradient(
        stops: [
          .init(color: AppColor.grayWhite, location: 0.0),
          .init(color: AppColor.grayWhite.opacity(0.98), location: 0.18),
          .init(color: AppColor.babyBlue50.opacity(isCompletion ? 0.44 : 0.58), location: 0.56),
          .init(color: AppColor.babyBlue100.opacity(isCompletion ? 0.74 : 0.86), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      LinearGradient(
        stops: [
          .init(color: Color.clear, location: 0.0),
          .init(color: AppColor.babyBlue50.opacity(isCompletion ? 0.0 : 0.26), location: 0.36),
          .init(color: AppColor.babyBlue150.opacity(isCompletion ? 0.0 : 0.18), location: 0.78),
          .init(color: AppColor.babyBlue200.opacity(isCompletion ? 0.0 : 0.12), location: 1.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      LinearGradient(
        stops: [
          .init(color: AppColor.grayWhite.opacity(0.72), location: 0.0),
          .init(color: Color.clear, location: isCompletion ? 0.34 : 0.24),
          .init(color: AppColor.babyBlue100.opacity(isCompletion ? 0.0 : 0.18), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .ignoresSafeArea()
  }

  private var isCompletion: Bool {
    step == .completion
  }
}

private enum OnboardingSurface {
  static let card = AppColor.grayWhite.opacity(0.9)
  static let input = AppColor.grayWhite.opacity(0.88)
  static let listRow = AppColor.grayWhite.opacity(0.82)
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
          .font(AppFont.title2Bold)
          .foregroundStyle(AppColor.moruTextStrong)
          .fixedSize(horizontal: false, vertical: true)

        Text(subtitle)
          .font(AppFont.label1NormalMedium)
          .foregroundStyle(AppColor.moruTextSecondary)
          .fixedSize(horizontal: false, vertical: true)
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
      subtitle: "맞춤 루틴을 설정해드릴게요"
    ) {
      VStack(spacing: AppSpacing.md) {
        ForEach(RoutineExperience.allCases) { experience in
          OnboardingOptionButton(
            title: experience.title,
            subtitle: experience.subtitle,
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

  var body: some View {
    OnboardingStepLayout(
      title: "어떤 목표로\n시작할까요?",
      subtitle: ""
    ) {
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.md) {
        ForEach(OnboardingDraft.goalOptions) { option in
          Button {
            viewModel.toggleGoal(tag: option.tag)
          } label: {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
              MoruSelectionIcon(icon: option.icon)
                .frame(width: 40, height: 40)

              Text(option.title)
                .font(AppFont.body1NormalSemiBold)
                .foregroundStyle(AppColor.moruTextStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

              Text(option.subtitle)
                .font(AppFont.caption1Medium)
                .foregroundStyle(AppColor.moruTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.md)
            .background(OnboardingSurface.card)
            .overlay(
              RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(
                  viewModel.draft.selectedGoalTags.contains(option.tag)
                    ? AppColor.orange350
                    : AppColor.moruBorder,
                  lineWidth: 1.5
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

private struct SuggestedRoutinePreviewView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    OnboardingStepLayout(
      title: "모루가 추천하는\n나만의 루틴이에요",
      subtitle: ""
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
      OnboardingStepLayout(
        title: "예상 루틴 시간은\n\(OnboardingDuration.totalMinutes(for: routine))분이에요",
        subtitle: "",
        titleSpacing: AppSpacing.fortyEight
      ) {
        OnboardingClockView(durationMinutes: OnboardingDuration.totalMinutes(for: routine))
          .frame(maxWidth: .infinity)
          .padding(.top, AppSpacing.xl)
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
      subtitle: "자연어로 편하게 입력하면 로컬 템플릿으로 정리해드려요",
      titleSpacing: AppSpacing.forty
    ) {
      VStack(alignment: .leading, spacing: AppSpacing.md) {
        ZStack(alignment: .topLeading) {
          if viewModel.draft.freeformText.isEmpty {
            Text("예) 일어나면 물 마시고, 스트레칭 하고, 일기 쓰고,\n오늘 할 일 미리 확인하기")
              .font(AppFont.label1NormalMedium)
              .foregroundStyle(AppColor.moruDisabled)
              .padding(AppSpacing.md)
          }

          TextEditor(text: $viewModel.draft.freeformText)
            .font(AppFont.body1NormalMedium)
            .foregroundStyle(AppColor.moruTextPrimary)
            .frame(minHeight: 158)
            .padding(AppSpacing.sm)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .background(OnboardingSurface.input)
        .overlay(
          RoundedRectangle(cornerRadius: AppRadius.sm)
            .stroke(AppColor.moruBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))

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
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)
      }
    }
  }
}

@MainActor
private struct RoutineOrganizingView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    OnboardingStepLayout(
      title: "루틴을 정리하고 있어요",
      subtitle: "잠시만 기다려주세요 ∙∙∙",
      titleSpacing: AppSpacing.fortyEight
    ) {
      VStack(spacing: AppSpacing.thirtySix) {
        Image("moruImageHalo")
          .resizable()
          .scaledToFit()
          .frame(width: 180, height: 180)

        VStack(alignment: .leading, spacing: AppSpacing.md) {
          OnboardingChecklistRow(title: "루틴 항목 파악", isDone: true)
          OnboardingChecklistRow(title: "유형 분류", isDone: true)
          OnboardingChecklistRow(title: "시간 배분 중", isDone: false)
        }
      }
      .frame(maxWidth: .infinity)
    }
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
      title: "정리된\n루틴이에요",
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
      title: "루틴 알림을\n설정해주세요",
      subtitle: "",
      titleSpacing: AppSpacing.forty
    ) {
      if let routine = viewModel.validatedPreviewRoutine {
        VStack(alignment: .leading, spacing: AppSpacing.twentyEight) {
          RoutineNameFields(routine: routine)

          VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("루틴 알림")
              .font(AppFont.heading3SemiBold)
              .foregroundStyle(AppColor.moruTextSecondary)

            HStack {
              Text("\(weekdaySummary) · \(viewModel.draft.formattedKoreanAlarmTime)")
                .font(AppFont.body1NormalSemiBold)
                .foregroundStyle(AppColor.moruTextSecondary)

              Spacer()

              Image(systemName: "chevron.up")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColor.moruTextSecondary)
            }

            TimeWheelControl(viewModel: viewModel)
            WeekdayCircleSelector(viewModel: viewModel)
            LocalAlarmSoundCard()
          }

          RoutineCountSummary(routine: routine)
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

private struct OnboardingVoiceSelectionView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    OnboardingStepLayout(
      title: "어떤 목소리로\n코칭 받을까요?",
      subtitle: "아침마다 들을 앱 내장 목소리예요. 들어보고 골라보세요.",
      titleSpacing: AppSpacing.forty
    ) {
      VStack(spacing: AppSpacing.md) {
        HStack(spacing: AppSpacing.xs) {
          Text("기본 음성")
            .font(AppFont.caption1SemiBold)
            .foregroundStyle(AppColor.orange350)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColor.orange100)
            .clipShape(Capsule())
          Text("앱 내장 음성")
            .font(AppFont.caption1Medium)
            .foregroundStyle(AppColor.moruTextSecondary)
          Spacer()
        }

        Image("moruVoiceOrb")
          .resizable()
          .scaledToFit()
          .frame(width: 156, height: 156)
          .frame(maxWidth: .infinity)

        ForEach(VoiceProfile.localVoices) { voice in
          MoruVoiceCard(
            name: voice.displayName,
            description: voice.assetVoiceCode,
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
      CompletionCheckmarkBadge()

      VStack(spacing: AppSpacing.md) {
        Text("루틴 설정이\n완료되었어요")
          .font(AppFont.title2Bold)
          .foregroundStyle(AppColor.moruTextStrong)
          .multilineTextAlignment(.center)
          .lineSpacing(2)

        Text("모루와 모닝 루틴 하러\n가볼까요?")
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary.opacity(0.74))
          .multilineTextAlignment(.center)
          .lineSpacing(2)
      }
      .padding(.top, AppSpacing.fortyEight)

      Spacer(minLength: AppSpacing.thirtySix)
    }
    .padding(.top, 160)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct CompletionCheckmarkBadge: View {
  var body: some View {
    ZStack {
      Circle()
        .fill(
          RadialGradient(
            colors: [
              AppColor.babyBlue50.opacity(0.98),
              AppColor.babyBlue100.opacity(0.88)
            ],
            center: .center,
            startRadius: 12,
            endRadius: 78
          )
        )

      Circle()
        .stroke(AppColor.babyBlue100.opacity(0.82), lineWidth: 1)

      Image(systemName: "checkmark")
        .font(.system(size: 58, weight: .semibold, design: .rounded))
        .foregroundStyle(AppColor.babyBlue300)
        .offset(x: 2, y: -1)
    }
    .frame(width: 160, height: 160)
    .shadow(color: AppColor.babyBlue300.opacity(0.34), radius: 24)
    .shadow(color: AppColor.babyBlue200.opacity(0.22), radius: 10, y: 6)
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
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextStrong)

      Text(errorMessage ?? "이전 단계에서 다시 시도해 주세요.")
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(AppSpacing.md)
    .background(OnboardingSurface.card)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
  }
}

private struct RoutineMetaPill: View {
  let goalTitle: String?
  let stepCount: Int
  let durationMinutes: Int

  var body: some View {
    HStack {
      Text(goalTitle.map { "\($0) 목표" } ?? "맞춤 루틴")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.orange350)

      Spacer()

      Text("\(stepCount)개 / 총 \(durationMinutes)분")
        .font(AppFont.label1NormalSemiBold)
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .padding(.horizontal, AppSpacing.lg)
    .frame(height: 42)
    .background(AppColor.grayWhite.opacity(0.82))
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
  }
}

private struct RoutineStepListCard: View {
  let routine: Routine

  var body: some View {
    VStack(spacing: AppSpacing.xs) {
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
    HStack(spacing: AppSpacing.sm) {
      ZStack {
        Circle()
          .fill(AppColor.orange100)
          .frame(width: 24, height: 24)

        Text("\(index)")
          .font(AppFont.caption1SemiBold)
          .foregroundStyle(AppColor.orange350)
      }

      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text(step.title)
          .font(AppFont.label1NormalSemiBold)
          .foregroundStyle(AppColor.moruTextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)

        Text("\(step.type.displayTitle) - \(step.durationTitle)")
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)
      }

      Spacer()
    }
    .padding(.horizontal, AppSpacing.md)
    .frame(height: 50)
    .background(OnboardingSurface.listRow)
    .overlay(
      RoundedRectangle(cornerRadius: AppRadius.sm)
        .stroke(AppColor.moruBorder, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
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
          .font(AppFont.heading3SemiBold)
          .foregroundStyle(AppColor.moruTextSecondary)

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
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextSecondary)

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
      .font(AppFont.body1NormalSemiBold)
      .foregroundStyle(isPlaceholder ? AppColor.moruDisabled : AppColor.moruTextPrimary)
      .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
      .padding(.horizontal, AppSpacing.md)
      .background(AppColor.grayWhite.opacity(0.74))
      .overlay(
        RoundedRectangle(cornerRadius: AppRadius.sm)
          .stroke(AppColor.moruBorder, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
  }
}

private struct RoutineCountSummary: View {
  let routine: Routine

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      Text("루틴 항목")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextSecondary)

      Text("\(routine.steps.count)개 - 총 \(OnboardingDuration.totalMinutes(for: routine))분")
        .font(AppFont.body1NormalSemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)
    }
  }
}

private struct OnboardingClockView: View {
  let durationMinutes: Int

  var body: some View {
    ZStack {
      Circle()
        .fill(AppColor.grayWhite.opacity(0.68))
        .frame(width: 190, height: 190)
        .shadow(color: AppColor.babyBlue300.opacity(0.2), radius: 14, y: 8)

      Circle()
        .stroke(AppColor.orange150, lineWidth: 8)
        .frame(width: 150, height: 150)

      VStack(spacing: AppSpacing.xxs) {
        Image(systemName: "clock")
          .font(.system(size: 36, weight: .medium))
          .foregroundStyle(AppColor.orange350)

        Text("\(durationMinutes)분")
          .font(AppFont.heading2SemiBold)
          .foregroundStyle(AppColor.moruTextStrong)
      }
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
        .foregroundStyle(isDone ? AppColor.orange350 : AppColor.moruDisabled)

      Text(title)
        .font(AppFont.label1NormalSemiBold)
        .foregroundStyle(isDone ? AppColor.moruTextPrimary : AppColor.moruTextSecondary)
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
        RoundedRectangle(cornerRadius: AppRadius.md)
          .fill(AppColor.gray200.opacity(0.52))
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
          .font(AppFont.heading2SemiBold)
          .foregroundStyle(AppColor.moruTextSecondary)
          .frame(width: 64, height: 36)
      }
      .buttonStyle(.plain)

      Text(current)
        .font(AppFont.title2Bold)
        .foregroundStyle(AppColor.moruTextSecondary)
        .frame(width: 64, height: 44)

      Button(action: increment) {
        Text(next)
          .font(AppFont.heading2SemiBold)
          .foregroundStyle(AppColor.moruTextSecondary)
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
            .font(AppFont.body1NormalSemiBold)
            .foregroundStyle(
              viewModel.draft.selectedWeekdays.contains(weekday)
                ? AppColor.grayWhite
                : AppColor.moruDisabled
            )
            .frame(width: 42, height: 42)
            .background(
              viewModel.draft.selectedWeekdays.contains(weekday)
                ? AppColor.orange350
                : AppColor.gray200
            )
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }
    }
  }
}

private struct LocalAlarmSoundCard: View {
  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.md) {
      HStack {
        Text("사운드")
          .font(AppFont.body1NormalSemiBold)
          .foregroundStyle(AppColor.moruTextSecondary)

        Spacer()

        Text("기본")
          .font(AppFont.body1NormalSemiBold)
          .foregroundStyle(AppColor.moruTextSecondary)
      }

      HStack(spacing: AppSpacing.sm) {
        Image(systemName: "speaker.wave.2")
          .font(.system(size: 26, weight: .medium))
          .foregroundStyle(AppColor.orange350)

        Capsule()
          .fill(AppColor.orange150)
          .frame(height: 4)
          .overlay(alignment: .leading) {
            Capsule()
              .fill(AppColor.orange350)
              .frame(width: 96, height: 4)
          }
      }

      Text("기본 알림음으로 저장됩니다.")
        .font(AppFont.caption1Medium)
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .padding(AppSpacing.md)
    .background(AppColor.grayWhite.opacity(0.66))
    .overlay(
      RoundedRectangle(cornerRadius: AppRadius.lg)
        .stroke(AppColor.moruBorder, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
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
            .font(AppFont.heading2SemiBold)
            .foregroundStyle(AppColor.moruTextStrong)

          Text(subtitle)
            .font(AppFont.body1NormalSemiBold)
            .foregroundStyle(AppColor.moruTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 24, weight: .medium))
          .foregroundStyle(AppColor.moruTextSecondary)
      }
      .padding(.horizontal, AppSpacing.lg)
      .frame(maxWidth: .infinity, minHeight: 84)
      .background(OnboardingSurface.card)
      .overlay(
        RoundedRectangle(cornerRadius: AppRadius.lg)
          .stroke(isSelected ? AppColor.orange350 : AppColor.moruBorder, lineWidth: 1.5)
      )
      .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
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

  var subtitle: String {
    switch self {
    case .firstTime:
      return "작게 시작할 수 있게 도와드릴게요."
    case .wantsRecommendation:
      return "목표에 맞는 로컬 템플릿을 보여드릴게요."
    case .hasRoutine:
      return "이미 하던 흐름을 정리해 볼게요."
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
