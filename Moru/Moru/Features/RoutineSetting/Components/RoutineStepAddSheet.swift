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
  let onDelete: (() -> Void)?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    initialStep: RoutineStepDraftState? = nil,
    onDelete: (() -> Void)? = nil,
    onSave: @escaping (RoutineStepDraftState) -> Void
  ) {
    self.initialStep = initialStep
    self.onDelete = onDelete
    self.onSave = onSave
    _title = State(initialValue: initialStep?.title ?? "")
    _selectedType = State(initialValue: initialStep?.type ?? .timer)
    _estimatedMinutes = State(initialValue: initialStep?.estimatedMinutes ?? 3)
  }

  var body: some View {
    VStack(spacing: 0) {
      Capsule()
        .fill(AppColor.moruBorder)
        .frame(width: 36, height: 3)
        .padding(.top, MoruPilotSpacing.eight)

      Text(initialStep == nil ? "항목 추가" : "항목 수정")
        .routineManagementTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)
        .padding(.top, MoruPilotSpacing.twenty)

      Divider()
        .overlay(MoruPilotColor.border)
        .padding(.top, MoruPilotSpacing.twenty)

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: MoruPilotSpacing.twenty) {
          nameField
          stepTypeSelector
          durationControl
          saveButton

          if initialStep != nil, let onDelete {
            deleteButton(onDelete)
          }
        }
        .padding(.horizontal, MoruPilotSpacing.twenty)
        .padding(.top, MoruPilotSpacing.twenty)
        .padding(.bottom, MoruPilotSpacing.twenty)
      }
    }
    .background(AppColor.grayWhite)
  }

  private var nameField: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.sixteen) {
      Text("항목명")
        .routineManagementTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)

      TextField("예) 물 한 잔 마시기", text: $title, axis: .vertical)
        .routineManagementTextStyle(.b4)
        .foregroundStyle(MoruPilotColor.textStrong)
        .tint(MoruPilotColor.accent)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        .padding(.horizontal, MoruPilotSpacing.sixteen)
        .padding(.vertical, MoruPilotSpacing.twelve)
        .frame(minHeight: 46)
        .background(
          RoundedRectangle(cornerRadius: MoruPilotRadius.card)
            .fill(AppColor.grayWhite)
            .overlay(
              RoundedRectangle(cornerRadius: MoruPilotRadius.card)
                .stroke(MoruPilotColor.border, lineWidth: 1)
            )
        )
    }
  }

  private var stepTypeSelector: some View {
    HStack(spacing: MoruPilotSpacing.eight) {
      ForEach(stepTypes, id: \.self) { type in
        stepTypeButton(type)
      }
    }
  }

  private var durationControl: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.sixteen) {
      Text("시간")
        .routineManagementTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)

      HStack {
        Button {
          estimatedMinutes = max(estimatedMinutes - 1, 1)
        } label: {
          MoruRoutineStepControlIcon(style: .minus)
            .opacity(estimatedMinutes == 1 ? 0.35 : 1)
            .frame(minWidth: 44, minHeight: 44)
        }
        .disabled(estimatedMinutes == 1)
        .buttonStyle(.plain)
        .accessibilityLabel("시간 1분 줄이기")

        Spacer()

        Text("\(estimatedMinutes)분")
          .routineManagementTextStyle(.b2.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textStrong)

        Spacer()

        Button {
          estimatedMinutes = min(estimatedMinutes + 1, 60)
        } label: {
          MoruRoutineStepControlIcon(style: .plus)
            .opacity(estimatedMinutes == 60 ? 0.35 : 1)
            .frame(minWidth: 44, minHeight: 44)
        }
        .disabled(estimatedMinutes == 60)
        .buttonStyle(.plain)
        .accessibilityLabel("시간 1분 늘리기")
      }
      .padding(.horizontal, MoruPilotSpacing.eight)
      .frame(minHeight: 52)
      .background(AppColor.moruSurfaceMuted)
      .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.card))
    }
  }

  private var saveButton: some View {
    Button {
      guard canSave else {
        return
      }

      onSave(
        RoutineStepDraftState(
          id: initialStep?.id ?? UUID(),
          presetItemID: initialStep?.presetItemID,
          type: selectedType,
          title: title.trimmingCharacters(in: .whitespacesAndNewlines),
          instruction: initialStep?.instruction ?? "",
          estimatedMinutes: estimatedMinutes,
          isRequired: initialStep?.isRequired ?? true
        )
      )
      dismiss()
    } label: {
      Text("저장")
        .routineManagementTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(AppColor.grayWhite)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 54)
        .background(canSave ? MoruPilotColor.accent : AppColor.moruDisabled)
        .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.pill))
    }
    .disabled(!canSave)
    .buttonStyle(.plain)
  }

  private func deleteButton(_ action: @escaping () -> Void) -> some View {
    Button {
      action()
      dismiss()
    } label: {
      Text("항목 삭제")
        .routineManagementTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 54)
        .background(AppColor.grayWhite)
        .overlay(
          RoundedRectangle(cornerRadius: MoruPilotRadius.pill)
            .stroke(MoruPilotColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.pill))
    }
    .buttonStyle(.plain)
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
        MoruRoutineStepTypeIcon(
          type: type,
          tint: isSelected ? MoruPilotColor.accent : nil
        )

        Text(type.routineSettingTitle)
          .routineManagementTextStyle(.c1)
          .foregroundStyle(
            isSelected ? AppColor.grayWhite : MoruPilotColor.textSecondary
          )
      }
      .frame(maxWidth: .infinity)
      .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 120 : 80)
      .background(
        isSelected ? MoruPilotColor.accentTint : AppColor.grayWhite
      )
      .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.card))
      .overlay(
        RoundedRectangle(cornerRadius: MoruPilotRadius.card)
          .stroke(
            isSelected ? MoruPilotColor.accentTint : MoruPilotColor.border,
            lineWidth: 1
          )
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
