//
//  EditableRoutineReviewForm.swift
//  Moru
//

import SwiftUI

struct EditableRoutineReviewForm: View {
  @ObservedObject var viewModel: OnboardingViewModel
  let routine: Routine

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.twentyEight) {
      EditableRoutineIdentityFields(viewModel: viewModel)
      routineCountSummary
      routineStepList
    }
  }

  private var routineCountSummary: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      sectionTitle("루틴 항목")

      Text("\(routine.steps.count)개 - 총 \(totalMinutes)분")
        .font(AppFont.body1NormalSemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)
    }
  }

  private var routineStepList: some View {
    VStack(spacing: AppSpacing.xs) {
      ForEach(Array(orderedSteps.enumerated()), id: \.element.id) { index, step in
        editableStepRow(index: index, step: step)
      }
    }
  }

  private func editableStepRow(
    index: Int,
    step: RoutineStep
  ) -> some View {
    HStack(spacing: AppSpacing.sm) {
      Text("\(index + 1)")
        .font(AppFont.caption1SemiBold)
        .foregroundStyle(AppColor.orange350)
        .frame(width: 24, height: 24)
        .background(AppColor.orange100)
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        TextField(
          "루틴 항목",
          text: stepTitleBinding(for: step.id)
        )
        .font(AppFont.label1NormalSemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

        Text("\(stepTypeTitle(step.type)) - \(durationTitle(step))")
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)
      }
    }
    .padding(.horizontal, AppSpacing.md)
    .frame(minHeight: 54)
    .background(AppColor.grayWhite.opacity(0.82))
    .overlay(fieldBorder)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(AppFont.heading3SemiBold)
      .foregroundStyle(AppColor.moruTextSecondary)
  }

  private var fieldBorder: some View {
    RoundedRectangle(cornerRadius: AppRadius.sm)
      .stroke(AppColor.moruBorder, lineWidth: 1)
  }

  private func stepTitleBinding(for stepID: UUID) -> Binding<String> {
    Binding(
      get: {
        viewModel.previewStepTitle(id: stepID)
      },
      set: { title in
        viewModel.updatePreviewStepTitle(id: stepID, title: title)
      }
    )
  }

  private var orderedSteps: [RoutineStep] {
    routine.steps.sorted { $0.order < $1.order }
  }

  private var totalMinutes: Int {
    routine.steps.reduce(0) { total, step in
      let seconds = max(0, step.estimatedSeconds ?? 60)
      return total + max(1, (seconds + 59) / 60)
    }
  }

  private func stepTypeTitle(_ type: RoutineStepType) -> String {
    switch type {
    case .confirm:
      return "확인형"
    case .timer:
      return "타이머형"
    case .input:
      return "입력형"
    }
  }

  private func durationTitle(_ step: RoutineStep) -> String {
    let seconds = max(0, step.estimatedSeconds ?? 60)
    return "\(max(1, (seconds + 59) / 60))분"
  }
}

struct EditableRoutineIdentityFields: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      Text("루틴")
        .onboardingTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textSecondary)

      EditableRoutineTextField(
        placeholder: "루틴 이름",
        text: Binding(
          get: { viewModel.previewName },
          set: { viewModel.previewName = $0 }
        )
      )
      EditableRoutineTextField(
        placeholder: "루틴 설명",
        text: Binding(
          get: { viewModel.previewSummary },
          set: { viewModel.previewSummary = $0 }
        )
      )
    }
  }
}

private struct EditableRoutineTextField: View {
  let placeholder: String
  @Binding var text: String
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    TextField(placeholder, text: $text, axis: .vertical)
      .onboardingTextStyle(.b4.weight(.semiBold))
      .foregroundStyle(MoruPilotColor.textPrimary)
      .tint(MoruPilotColor.accent)
      .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
      .padding(.horizontal, MoruPilotSpacing.sixteen)
      .padding(.vertical, MoruPilotSpacing.twelve)
      .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 72 : 48)
      .background(OnboardingSurface.input)
      .overlay(
        RoundedRectangle(cornerRadius: MoruPilotRadius.card)
          .stroke(MoruPilotColor.border, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.card))
  }
}
