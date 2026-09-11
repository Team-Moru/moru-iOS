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
        .fill(MoruColor.border)
        .frame(width: 36, height: 3)
        .padding(.top, MoruSpacing.eight)

      Text(initialStep == nil ? "항목 추가" : "항목 수정")
        .moruTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruColor.textStrong)
        .padding(.top, MoruSpacing.twenty)

      Divider()
        .overlay(MoruColor.border)
        .padding(.top, MoruSpacing.twenty)

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: MoruSpacing.twenty) {
          nameField
          stepTypeSelector
          durationControl
          saveButton

          if initialStep != nil, let onDelete {
            deleteButton(onDelete)
          }
        }
        .padding(.horizontal, MoruSpacing.twenty)
        .padding(.top, MoruSpacing.twenty)
        .padding(.bottom, MoruSpacing.twenty)
      }
    }
    .background(AppColor.grayWhite)
  }

  private var nameField: some View {
    VStack(alignment: .leading, spacing: MoruSpacing.sixteen) {
      Text("항목명")
        .moruTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruColor.textStrong)

      TextField("예) 물 한 잔 마시기", text: $title, axis: .vertical)
        .moruTextStyle(.b4)
        .foregroundStyle(MoruColor.textStrong)
        .tint(MoruColor.accent)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        .padding(.horizontal, MoruSpacing.sixteen)
        .padding(.vertical, MoruSpacing.twelve)
        .frame(minHeight: 46)
        .background(
          RoundedRectangle(cornerRadius: MoruRadius.card)
            .fill(AppColor.grayWhite)
            .overlay(
              RoundedRectangle(cornerRadius: MoruRadius.card)
                .stroke(MoruColor.border, lineWidth: 1)
            )
        )
    }
  }

  private var stepTypeSelector: some View {
    HStack(spacing: MoruSpacing.eight) {
      ForEach(stepTypes, id: \.self) { type in
        stepTypeButton(type)
      }
    }
  }

  private var durationControl: some View {
    VStack(alignment: .leading, spacing: MoruSpacing.sixteen) {
      Text("시간")
        .moruTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruColor.textStrong)

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
          .moruTextStyle(.b2.weight(.semiBold))
          .foregroundStyle(MoruColor.textStrong)

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
      .padding(.horizontal, MoruSpacing.eight)
      .frame(minHeight: 52)
      .background(MoruColor.surfaceMuted)
      .clipShape(RoundedRectangle(cornerRadius: MoruRadius.card))
    }
  }

  private var saveButton: some View {
    MoruButton("저장", isEnabled: canSave) {
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
    }
  }

  private func deleteButton(_ action: @escaping () -> Void) -> some View {
    MoruButton("항목 삭제", style: .secondary) {
      action()
      dismiss()
    }
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
          tint: isSelected ? MoruColor.accent : nil
        )

        Text(type.routineSettingTitle)
          .moruTextStyle(.c1)
          .foregroundStyle(
            isSelected ? MoruColor.accent : MoruColor.textSecondary
          )
      }
      .frame(maxWidth: .infinity)
      .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 120 : 80)
      .background(
        isSelected ? MoruColor.accentTint : AppColor.grayWhite
      )
      .clipShape(RoundedRectangle(cornerRadius: MoruRadius.card))
      .overlay(
        RoundedRectangle(cornerRadius: MoruRadius.card)
          .stroke(
            isSelected ? MoruColor.accentTint : MoruColor.border,
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
