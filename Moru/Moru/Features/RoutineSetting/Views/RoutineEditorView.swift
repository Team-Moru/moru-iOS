//
//  RoutineEditorView.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

private struct RoutineStepFramePreferenceKey: PreferenceKey {
  static var defaultValue: [UUID: CGRect] = [:]

  static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

struct RoutineEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var draft: RoutineDraftState
  @State private var isStepAddSheetPresented = false
  @State private var isScheduleExpanded: Bool
  @State private var isDeleteDialogPresented = false
  @State private var activeRoutineConflict: RoutineActivationConflictState?
  @State private var selectedEditStepIndex: Int? = nil
  @State private var isStepEditSheetPresented = false
  @State private var saveErrorMessage: String?
  @State private var draggingStepID: UUID?
  @State private var dragStartFrame: CGRect?
  @State private var dragTranslation: CGFloat = 0
  @State private var dragTouchYOffsetFromCenter: CGFloat = 0
  @State private var stepFrames: [UUID: CGRect] = [:]

  let onSave: (RoutineDraftState) async -> Bool
  let onReplaceActiveRoutine: (RoutineDraftState) async -> Bool
  let onDelete: ((UUID) async -> Bool)?
  let activeRoutineConflictState:
    (RoutineDraftState) -> RoutineActivationConflictState?

  init(
    draft: RoutineDraftState,
    initialScheduleExpanded: Bool = false,
    onSave: @escaping (RoutineDraftState) async -> Bool,
    onReplaceActiveRoutine: @escaping (RoutineDraftState) async -> Bool,
    onDelete: ((UUID) async -> Bool)? = nil,
    activeRoutineConflictState:
      @escaping (RoutineDraftState) -> RoutineActivationConflictState? = { _ in nil }
  ) {
    self._draft = State(initialValue: draft)
    self._isScheduleExpanded = State(initialValue: initialScheduleExpanded)
    self.onSave = onSave
    self.onReplaceActiveRoutine = onReplaceActiveRoutine
    self.onDelete = onDelete
    self.activeRoutineConflictState = activeRoutineConflictState
  }

  var body: some View {
    NavigationStack {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
          titleSection
            .padding(.top, dynamicTypeSize.isAccessibilitySize ? 28 : 20)

          alarmSection
            .padding(.top, MoruSpacing.thirtySix)

          stepSection
            .padding(.top, MoruSpacing.thirtySix)

          if let saveErrorMessage {
            Text(saveErrorMessage)
              .moruTextStyle(.c1)
              .foregroundStyle(MoruColor.accent)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.top, MoruSpacing.sixteen)
          }
        }
        .padding(.horizontal, MoruSpacing.gutter)
        .padding(.top, MoruSpacing.eight)
      }
      .defaultScrollAnchor(.top)
      .background(MoruColor.canvas.ignoresSafeArea())
      .navigationTitle(draft.routineID == nil ? "루틴 만들기" : "루틴 수정")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          backButton
        }
        if draft.routineID != nil {
          ToolbarItem(placement: .destructiveAction) {
            deleteButton
          }
        }
      }
      .safeAreaBar(edge: .bottom) {
        MoruButton(
          draft.routineID == nil
            ? RoutineManagementCopy.createCompletion
            : RoutineManagementCopy.editCompletion,
          isEnabled: draft.canSave
        ) {
          guard draft.canSave else {
            return
          }

          if let conflict = activeRoutineConflictState(draft) {
            activeRoutineConflict = conflict
            return
          }

          Task {
            await saveAndDismissIfNeeded()
          }
        }
        .padding(.horizontal, MoruSpacing.twenty)
        .padding(.vertical, MoruSpacing.eight)
      }
      .sheet(isPresented: $isStepAddSheetPresented) {
        RoutineStepAddSheet { step in
          draft.steps.append(step)
        }
        .presentationDetents(
          dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(499)]
        )
        .presentationDragIndicator(.hidden)
        .presentationBackground(AppColor.grayWhite)
        .presentationCornerRadius(AppRadius.lg)
      }
      .sheet(isPresented: $isStepEditSheetPresented) {
        if let index = selectedEditStepIndex, draft.steps.indices.contains(index) {
          let stepID = draft.steps[index].id
          RoutineStepAddSheet(
            initialStep: draft.steps[index],
            onDelete: {
              removeStep(stepID)
            }
          ) { updatedStep in
            guard let currentIndex = draft.steps.firstIndex(
              where: { $0.id == updatedStep.id }
            ) else {
              return
            }

            draft.steps[currentIndex] = updatedStep
          }
          .presentationDetents(
            dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(559)]
          )
          .presentationDragIndicator(.hidden)
          .presentationBackground(AppColor.grayWhite)
          .presentationCornerRadius(AppRadius.lg)
        }
      }
      .alert(
        RoutineManagementCopy.deleteConfirmationTitle,
        isPresented: $isDeleteDialogPresented
      ) {
        Button(RoutineManagementCopy.deleteConfirmationCancelTitle, role: .cancel) {}
        Button(RoutineManagementCopy.deleteConfirmationDeleteTitle, role: .destructive) {
          if let routineID = draft.routineID {
            Task {
              let didDelete = await onDelete?(routineID) ?? false
              isDeleteDialogPresented = false
              if didDelete {
                dismiss()
              } else {
                saveErrorMessage =
                  "알람 취소에 실패해 루틴을 삭제하지 않았어요."
              }
            }
          } else {
            isDeleteDialogPresented = false
            dismiss()
          }
        }
      } message: {
        Text(RoutineManagementCopy.deleteConfirmationMessage)
      }
      .alert(
        RoutineManagementCopy.activeRoutineReplacementTitle,
        isPresented: Binding(
          get: { activeRoutineConflict != nil },
          set: { isPresented in
            if !isPresented {
              activeRoutineConflict = nil
            }
          }
        ),
        presenting: activeRoutineConflict
      ) { _ in
        Button("취소", role: .cancel) {
          activeRoutineConflict = nil
        }
        Button("변경하기") {
          Task {
            await replaceActiveRoutineAndDismissIfNeeded()
          }
        }
      } message: { conflict in
        Text(RoutineManagementCopy.activeRoutineReplacementMessage(conflict))
      }
    }
  }

  private var backButton: some View {
    Button {
      dismiss()
    } label: {
      Image(systemName: "xmark")
    }
    .accessibilityLabel("닫기")
  }

  private var deleteButton: some View {
    Button(role: .destructive) {
      isDeleteDialogPresented = true
    } label: {
      Text("삭제")
    }
    // role: .destructive만으로는 이 툴바 자리에서 빨간 강조가 나오지 않아 직접 tint한다.
    .tint(.red)
  }

  private var titleSection: some View {
    VStack(alignment: .leading, spacing: MoruSpacing.twelve) {
      sectionTitle("루틴")

      VStack(spacing: MoruSpacing.eight) {
        editorInputRow(text: $draft.title, placeholder: "루틴 이름")
        editorInputRow(text: $draft.summary, placeholder: "루틴 설명")
      }
    }
  }

  private var alarmSection: some View {
    VStack(alignment: .leading, spacing: MoruSpacing.twelve) {
      sectionTitle("루틴 알림")

      Button {
        withAnimation(.snappy(duration: 0.2)) {
          isScheduleExpanded.toggle()
        }
      } label: {
        HStack(spacing: MoruSpacing.sixteen) {
          Text(alarmTitle)
            .moruTextStyle(.b4)
            .foregroundStyle(MoruColor.textSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

          Spacer(minLength: 0)

          MoruChevron(
            color: MoruColor.textPrimary,
            direction: .down
          )
          .rotationEffect(isScheduleExpanded ? .degrees(180) : .zero)
          .frame(minWidth: 44, minHeight: 44)
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel("루틴 알림 \(alarmTitle)")
      .accessibilityValue(isScheduleExpanded ? "펼쳐짐" : "접힘")

      if isScheduleExpanded {
        RoutineScheduleSettingView(
          hour: $draft.hour,
          minute: $draft.minute,
          selectedWeekdays: $draft.selectedWeekdays
        )
        .padding(.top, MoruSpacing.four)
      }
    }
  }

  private var stepSection: some View {
    VStack(alignment: .leading, spacing: MoruSpacing.twelve) {
      HStack(alignment: .firstTextBaseline, spacing: MoruSpacing.twelve) {
        sectionTitle("루틴 항목")

        Text("\(draft.steps.count)개 - 총 \(totalMinutes)분")
          .moruTextStyle(.c1)
          .foregroundStyle(MoruColor.textTertiary)
          .fixedSize(horizontal: false, vertical: true)

        Spacer()
      }

      ZStack {
        VStack(spacing: MoruSpacing.ten) {
          ForEach($draft.steps) { $step in
            let stepID = step.id
            let order = stepOrder(for: stepID)

            RoutineStepDraftRow(
              step: $step,
              order: order,
              onDelete: {
                resetStepDragState()
                removeStep(stepID)
              },
              onTapCard: {
                guard draggingStepID == nil else {
                  return
                }

                if let index = draft.steps.firstIndex(where: { $0.id == stepID }) {
                  selectedEditStepIndex = index
                  isStepEditSheetPresented = true
                }
              }
            )
            .opacity(draggingStepID == stepID ? 0 : 1)
            .background(
              GeometryReader { proxy in
                Color.clear.preference(
                  key: RoutineStepFramePreferenceKey.self,
                  value: [stepID: proxy.frame(in: .named("routineStepList"))]
                )
              }
            )
            .gesture(stepReorderGesture(for: stepID))
          }
        }

        if let draggingStepID,
           let dragStartFrame,
           let index = draft.steps.firstIndex(where: { $0.id == draggingStepID }) {
          RoutineStepDraftRow(
            step: $draft.steps[index],
            order: stepOrder(for: draggingStepID),
            onDelete: {},
            onTapCard: {}
          )
          .frame(width: dragStartFrame.width, height: dragStartFrame.height)
          .position(
            x: dragStartFrame.midX,
            y: dragStartFrame.midY + dragTranslation
          )
          .shadow(
            color: MoruColor.shadow.opacity(0.7),
            radius: 14,
            x: 0,
            y: 4
          )
          .allowsHitTesting(false)
        }
      }
      .coordinateSpace(name: "routineStepList")
      .onPreferenceChange(RoutineStepFramePreferenceKey.self) { frames in
        stepFrames = frames
      }

      addStepButton
    }
  }

  private var addStepButton: some View {
    Button {
      isStepAddSheetPresented = true
    } label: {
      HStack(spacing: MoruSpacing.eight) {
        MoruRoutineStepControlIcon(style: .plus)
          .frame(width: 18, height: 18)

        Text(RoutineManagementCopy.addStep)
          .moruTextStyle(.b4.weight(.semiBold))
          .foregroundStyle(MoruColor.textTertiary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity)
      .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 88 : 62)
      .background(AppColor.grayWhite)
      .clipShape(RoundedRectangle(cornerRadius: MoruRadius.card))
      .overlay(
        RoundedRectangle(cornerRadius: MoruRadius.card)
          .stroke(MoruColor.border, lineWidth: 1)
      )
      .shadow(color: MoruColor.shadow, radius: 7.5, x: 0, y: 0)
    }
    .buttonStyle(.plain)
  }
  private func saveAndDismissIfNeeded() async {
    saveErrorMessage = nil

    if await onSave(draft) {
      dismiss()
    } else {
      saveErrorMessage = "루틴을 저장하지 못했어요. 다시 시도해 주세요."
    }
  }

  private func replaceActiveRoutineAndDismissIfNeeded() async {
    saveErrorMessage = nil

    if await onReplaceActiveRoutine(draft) {
      activeRoutineConflict = nil
      dismiss()
    } else {
      activeRoutineConflict = nil
      saveErrorMessage = "루틴을 저장하지 못했어요. 다시 시도해 주세요."
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .moruTextStyle(.b4.weight(.semiBold))
      .foregroundStyle(MoruColor.textPrimary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func editorInputRow(
    text: Binding<String>,
    placeholder: String
  ) -> some View {
    TextField(placeholder, text: text, axis: .vertical)
      .moruTextStyle(.b4)
      .foregroundStyle(MoruColor.textStrong)
      .tint(MoruColor.accent)
      .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
      .padding(.horizontal, MoruSpacing.sixteen)
      .padding(.vertical, MoruSpacing.twelve)
      .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 72 : 48)
      .background(inputBackground)
  }

  private var inputBackground: some View {
    RoundedRectangle(cornerRadius: MoruRadius.card)
      .fill(AppColor.grayWhite.opacity(0.4))
      .overlay(
        RoundedRectangle(cornerRadius: MoruRadius.card)
          .stroke(MoruColor.border, lineWidth: 1)
      )
  }

  private var alarmTitle: String {
    RoutineManagementCopy.scheduleSummary(
      weekdays: draft.selectedWeekdays,
      hour: draft.hour,
      minute: draft.minute
    )
  }

  private var totalMinutes: Int {
    draft.steps.map(\.estimatedMinutes).reduce(0, +)
  }

  private func stepOrder(for stepID: UUID) -> Int {
    guard let index = draft.steps.firstIndex(where: { $0.id == stepID }) else {
      return 1
    }

    return index + 1
  }

  private func removeStep(_ stepID: UUID) {
    guard let index = draft.steps.firstIndex(where: { $0.id == stepID }) else {
      return
    }

    draft.steps.remove(at: index)
  }

  private func stepReorderGesture(for stepID: UUID) -> some Gesture {
    LongPressGesture(minimumDuration: 0.18)
      .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("routineStepList")))
      .onChanged { value in
        switch value {
        case .first:
          break
        case .second(true, let drag):
          guard
            let drag,
            let stepFrame = dragStartFrame ?? stepFrames[stepID]
          else {
            return
          }

          if draggingStepID == nil {
            draggingStepID = stepID
            dragStartFrame = stepFrame
            dragTouchYOffsetFromCenter = stepFrame.midY - drag.startLocation.y
          }

          let floatingCenterY = drag.location.y + dragTouchYOffsetFromCenter
          dragTranslation = floatingCenterY - stepFrame.midY
          reorderDraggedStep(stepID, floatingCenterY: floatingCenterY)
        default:
          break
        }
      }
      .onEnded { _ in
        withAnimation(.snappy(duration: 0.18)) {
          resetStepDragState()
        }
      }
  }

  private func reorderDraggedStep(_ stepID: UUID, floatingCenterY: CGFloat) {
    guard
      let sourceIndex = draft.steps.firstIndex(where: { $0.id == stepID })
    else {
      return
    }

    let movedStep = draft.steps[sourceIndex]
    var remainingSteps = draft.steps
    remainingSteps.remove(at: sourceIndex)

    var insertionIndex = remainingSteps.endIndex
    for (index, step) in remainingSteps.enumerated() {
      guard let frame = stepFrames[step.id] else {
        continue
      }

      if floatingCenterY < frame.midY {
        insertionIndex = index
        break
      }
    }

    remainingSteps.insert(movedStep, at: insertionIndex)

    guard remainingSteps.map(\.id) != draft.steps.map(\.id) else {
      return
    }

    withAnimation(.snappy(duration: 0.2)) {
      draft.steps = remainingSteps
    }
  }

  private func resetStepDragState() {
    draggingStepID = nil
    dragStartFrame = nil
    dragTranslation = 0
    dragTouchYOffsetFromCenter = 0
  }
}

#if DEBUG
#Preview {
  RoutineEditorView(
    draft: RoutineDraftState(
      title: "활력 루틴",
      steps: [
        RoutineStepDraftState(type: .confirm, title: "잠자리 정리하기", estimatedMinutes: 1),
        RoutineStepDraftState(type: .timer, title: "심호흡하며 명상하기", estimatedMinutes: 3),
        RoutineStepDraftState(type: .input, title: "오늘의 다짐 확인하기", estimatedMinutes: 1),
      ]
    ),
    onSave: { _ in true },
    onReplaceActiveRoutine: { _ in true }
  )
}
#endif
