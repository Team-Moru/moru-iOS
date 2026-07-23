//
//  EditableRoutineReviewForm.swift
//  Moru
//

import SwiftUI

struct EditableRoutineReviewForm: View {
  @ObservedObject var viewModel: OnboardingViewModel
  let routine: Routine
  let alarmSummary: String

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.twentyEight) {
      routineNameSection
      alarmSection
      routineCountSummary
      routineStepList
    }
  }

  private var routineNameSection: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      sectionTitle("루틴 이름")
      EditableRoundedTextField(
        placeholder: "루틴 이름",
        text: previewNameBinding
      )
      EditableRoundedTextField(
        placeholder: "루틴 설명",
        text: previewSummaryBinding
      )
    }
  }

  private var alarmSection: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      sectionTitle("루틴 알림")

      Text(alarmSummary)
        .font(AppFont.body1NormalSemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.horizontal, AppSpacing.md)
        .background(AppColor.grayWhite.opacity(0.74))
        .overlay(fieldBorder)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
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

  private var previewNameBinding: Binding<String> {
    Binding(
      get: { viewModel.previewName },
      set: { name in
        viewModel.previewName = name
      }
    )
  }

  private var previewSummaryBinding: Binding<String> {
    Binding(
      get: { viewModel.previewSummary },
      set: { summary in
        viewModel.previewSummary = summary
      }
    )
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

private struct EditableRoundedTextField: View {
  let placeholder: String
  @Binding var text: String

  var body: some View {
    TextField(placeholder, text: $text)
      .font(AppFont.body1NormalSemiBold)
      .foregroundStyle(AppColor.moruTextPrimary)
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
