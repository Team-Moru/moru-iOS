//
//  RoutineStepAddSheet.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct RoutineStepAddSheet: View {
  @Environment(\.dismiss) private var dismiss

  @State private var title = ""
  @State private var selectedType: RoutineStepType = .timer
  @State private var estimatedMinutes = 3

  let initialStep: RoutineStepDraftState?
  let onSave: (RoutineStepDraftState) -> Void

  init(
    initialStep: RoutineStepDraftState? = nil,
    onSave: @escaping (RoutineStepDraftState) -> Void
  ) {
    self.initialStep = initialStep
    self.onSave = onSave
    _title = State(initialValue: initialStep?.title ?? "")
    _selectedType = State(initialValue: initialStep?.type ?? .timer)
    _estimatedMinutes = State(initialValue: initialStep?.estimatedMinutes ?? 3)
  }

  var body: some View {
    VStack(spacing: AppSpacing.lg) {
      Capsule()
        .fill(AppColor.moruBorder)
        .frame(width: 36, height: 3)

      Text(initialStep == nil ? "항목 추가" : "항목 수정")
        .font(AppFont.body1NormalSemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      VStack(alignment: .leading, spacing: AppSpacing.xs) {
        Text("항목명")
          .font(AppFont.label1NormalSemiBold)
          .foregroundStyle(AppColor.moruTextPrimary)

        TextField("예) 물 한 잔 마시기", text: $title)
          .font(AppFont.label1NormalMedium)
          .foregroundStyle(AppColor.moruTextPrimary)
          .tint(AppColor.orange350)
          .padding(.horizontal, AppSpacing.md)
          .frame(height: 44)
          .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
              .fill(AppColor.grayWhite)
              .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                  .stroke(AppColor.moruBorder, lineWidth: 1)
              )
          )
      }

      HStack(spacing: AppSpacing.six) {
        ForEach(stepTypes, id: \.self) { type in
          stepTypeButton(type)
        }
      }

      VStack(alignment: .leading, spacing: AppSpacing.xs) {
        Text("시간")
          .font(AppFont.label1NormalSemiBold)
          .foregroundStyle(AppColor.moruTextPrimary)

        HStack {
          Button {
            estimatedMinutes = max(estimatedMinutes - 1, 1)
          } label: {
            MoruRoutineStepControlIcon(style: .minus)
              .opacity(estimatedMinutes == 1 ? 0.35 : 1)
          }
          .disabled(estimatedMinutes == 1)
          .buttonStyle(.plain)

          Spacer()

          Text("\(estimatedMinutes)분")
            .font(AppFont.body1NormalSemiBold)
            .foregroundStyle(AppColor.moruTextPrimary)

          Spacer()

          Button {
            estimatedMinutes = min(estimatedMinutes + 1, 60)
          } label: {
            MoruRoutineStepControlIcon(style: .plus)
              .opacity(estimatedMinutes == 60 ? 0.35 : 1)
          }
          .disabled(estimatedMinutes == 60)
          .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.md)
        .frame(height: 38)
        .background(AppColor.moruSurfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
      }

      Button {
        guard canSave else {
          return
        }

        onSave(
          RoutineStepDraftState(
            id: initialStep?.id ?? UUID(),
            type: selectedType,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            estimatedMinutes: estimatedMinutes
          )
        )
        dismiss()
      } label: {
        Text("저장")
          .font(AppFont.label1NormalSemiBold)
          .foregroundStyle(AppColor.grayWhite)
          .frame(maxWidth: .infinity)
          .frame(height: 48)
          .background(canSave ? AppColor.orange350 : AppColor.moruDisabled)
          .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
      }
      .disabled(!canSave)
      .buttonStyle(.plain)
    }
    .padding(.horizontal, AppSpacing.md)
    .padding(.top, AppSpacing.xs)
    .padding(.bottom, AppSpacing.lg)
    .background(AppColor.grayWhite)
  }

  private var stepTypes: [RoutineStepType] {
    [.timer, .confirm, .input]
  }

  private var canSave: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func stepTypeButton(_ type: RoutineStepType) -> some View {
    let isSelected = selectedType == type

    return Button {
      selectedType = type
    } label: {
      VStack(spacing: AppSpacing.xs) {
        MoruRoutineStepTypeIcon(type: type)

        Text(type.routineSettingTitle)
          .font(AppFont.caption1Medium)
          .foregroundStyle(isSelected ? AppColor.orange350 : AppColor.moruTextSecondary)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 100)
      .background(isSelected ? AppColor.orange150 : AppColor.grayWhite)
      .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
      .overlay(
        RoundedRectangle(cornerRadius: AppRadius.md)
          .stroke(isSelected ? AppColor.orange150 : AppColor.moruBorder, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }
}

#if DEBUG
#Preview {
  RoutineStepAddSheet { _ in }
}
#endif
