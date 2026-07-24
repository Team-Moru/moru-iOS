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
  @State private var weekdayConflict: RoutineWeekdayConflictState?
  @State private var selectedEditStepIndex: Int? = nil
  @State private var isStepEditSheetPresented = false
  @State private var saveErrorMessage: String?
  @State private var draggingStepID: UUID?
  @State private var dragStartFrame: CGRect?
  @State private var dragTranslation: CGFloat = 0
  @State private var dragTouchYOffsetFromCenter: CGFloat = 0
  @State private var stepFrames: [UUID: CGRect] = [:]

  let onSave: (RoutineDraftState) async -> Bool
  let onResolveWeekdayConflict: (RoutineDraftState) async -> Bool
  let onDelete: ((UUID) async -> Bool)?
  let weekdayConflictState: (RoutineDraftState) -> RoutineWeekdayConflictState?

  init(
    draft: RoutineDraftState,
    initialScheduleExpanded: Bool = false,
    onSave: @escaping (RoutineDraftState) async -> Bool,
    onResolveWeekdayConflict: @escaping (RoutineDraftState) async -> Bool,
    onDelete: ((UUID) async -> Bool)? = nil,
    weekdayConflictState: @escaping (RoutineDraftState) -> RoutineWeekdayConflictState? = { _ in nil }
  ) {
    self._draft = State(initialValue: draft)
    self._isScheduleExpanded = State(initialValue: initialScheduleExpanded)
    self.onSave = onSave
    self.onResolveWeekdayConflict = onResolveWeekdayConflict
    self.onDelete = onDelete
    self.weekdayConflictState = weekdayConflictState
  }

  var body: some View {
    NavigationStack {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
          editorHeader

          titleSection
            .padding(.top, dynamicTypeSize.isAccessibilitySize ? 28 : 20)

          alarmSection
            .padding(.top, MoruPilotSpacing.thirtySix)

          stepSection
            .padding(.top, MoruPilotSpacing.thirtySix)

          if let saveErrorMessage {
            Text(saveErrorMessage)
              .routineManagementTextStyle(.c1)
              .foregroundStyle(MoruPilotColor.accent)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.top, MoruPilotSpacing.sixteen)
          }
        }
        .padding(.horizontal, MoruPilotSpacing.twenty)
        .padding(.top, MoruPilotSpacing.eight)
        .padding(.bottom, 112)
      }
      .defaultScrollAnchor(.top)
      .background(MoruPilotColor.canvas.ignoresSafeArea())
      .toolbar(.hidden, for: .navigationBar)
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: AppSpacing.none) {
          Button {
            guard draft.canSave else {
              return
            }

            if let conflict = weekdayConflictState(draft) {
              weekdayConflict = conflict
              return
            }

            Task {
              await saveAndDismissIfNeeded()
            }
          } label: {
            Text(
              draft.routineID == nil
                ? RoutineManagementCopy.createCompletion
                : RoutineManagementCopy.editCompletion
            )
              .routineManagementTextStyle(.b4.weight(.semiBold))
              .foregroundStyle(AppColor.grayWhite)
              .frame(maxWidth: .infinity)
              .frame(minHeight: 54)
              .background(
                draft.canSave ? MoruPilotColor.accent : AppColor.moruDisabled
              )
              .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.pill))
          }
          .disabled(!draft.canSave)
          .buttonStyle(.plain)
        }
        .padding(.horizontal, MoruPilotSpacing.twenty)
        .padding(.top, MoruPilotSpacing.eight)
        .padding(.bottom, MoruPilotSpacing.eight)
        .background(MoruPilotColor.canvas.opacity(0.94))
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
      .overlay {
        if isDeleteDialogPresented {
          deleteDialogOverlay
        }

        if let weekdayConflict {
          weekdayConflictDialogOverlay(weekdayConflict)
        }
      }
    }
  }

  private var editorHeader: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: MoruPilotSpacing.eight) {
          HStack {
            backButton
            Spacer()
            deleteButton
          }

          editorTitle
        }
      } else {
        ZStack {
          editorTitle

          HStack {
            backButton
            Spacer()
            deleteButton
          }
        }
      }
    }
    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 96 : 44)
  }

  private var editorTitle: some View {
    Text(draft.routineID == nil ? "루틴 만들기" : "루틴 수정")
      .routineManagementTextStyle(.b3.weight(.semiBold))
      .foregroundStyle(MoruPilotColor.textStrong)
      .frame(maxWidth: .infinity)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityAddTraits(.isHeader)
  }

  private var backButton: some View {
    Button {
      dismiss()
    } label: {
      Text("뒤로")
        .routineManagementTextStyle(.b4)
        .foregroundStyle(MoruPilotColor.textSecondary)
        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
    }
    .buttonStyle(.plain)
  }

  private var deleteButton: some View {
    Button {
      isDeleteDialogPresented = true
    } label: {
      Text("삭제")
        .routineManagementTextStyle(.b4)
        .foregroundStyle(MoruPilotColor.textSecondary)
        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
    }
    .opacity(draft.routineID == nil ? 0 : 1)
    .disabled(draft.routineID == nil)
    .buttonStyle(.plain)
    .accessibilityHidden(draft.routineID == nil)
  }

  private var titleSection: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.twelve) {
      sectionTitle("루틴 이름")

      VStack(spacing: MoruPilotSpacing.eight) {
        editorInputRow(text: $draft.title, placeholder: "루틴 이름")
        editorInputRow(text: $draft.summary, placeholder: "루틴 설명")
      }
    }
  }

  private var alarmSection: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.twelve) {
      sectionTitle("루틴 알림")

      Button {
        withAnimation(.snappy(duration: 0.2)) {
          isScheduleExpanded.toggle()
        }
      } label: {
        HStack(spacing: MoruPilotSpacing.sixteen) {
          Text(alarmTitle)
            .routineManagementTextStyle(.b4)
            .foregroundStyle(MoruPilotColor.textSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

          Spacer(minLength: 0)

          MoruChevron(
            color: MoruPilotColor.textPrimary,
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
        .padding(.top, MoruPilotSpacing.four)
      }
    }
  }

  private var stepSection: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.twelve) {
      HStack(alignment: .firstTextBaseline, spacing: MoruPilotSpacing.twelve) {
        sectionTitle("루틴 항목")

        Text("\(draft.steps.count)개 - 총 \(totalMinutes)분")
          .routineManagementTextStyle(.c1)
          .foregroundStyle(MoruPilotColor.textTertiary)
          .fixedSize(horizontal: false, vertical: true)

        Spacer()
      }

      ZStack {
        VStack(spacing: MoruPilotSpacing.ten) {
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
            color: MoruPilotColor.shadow.opacity(0.7),
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
      HStack(spacing: MoruPilotSpacing.eight) {
        MoruRoutineStepControlIcon(style: .plus)
          .frame(width: 18, height: 18)

        Text(RoutineManagementCopy.addStep)
          .routineManagementTextStyle(.b4.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textTertiary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity)
      .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 88 : 62)
      .background(AppColor.grayWhite)
      .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.card))
      .overlay(
        RoundedRectangle(cornerRadius: MoruPilotRadius.card)
          .stroke(MoruPilotColor.border, lineWidth: 1)
      )
      .shadow(color: MoruPilotColor.shadow, radius: 7.5, x: 0, y: 0)
    }
    .buttonStyle(.plain)
  }
  private var deleteDialogOverlay: some View {
    ZStack {
      AppColor.grayBlack
        .opacity(0.22)
        .ignoresSafeArea()

      MoruDialog(
        title: "이 루틴을 삭제할까요?",
        message: "삭제한 루틴은\n되돌릴 수 없어요.",
        primaryTitle: "뒤로가기",
        secondaryTitle: "삭제하기",
        primaryAction: {
          isDeleteDialogPresented = false
        },
        secondaryAction: {
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
      )
    }
  }

  private func weekdayConflictDialogOverlay(_ conflict: RoutineWeekdayConflictState) -> some View {
    ZStack {
      AppColor.grayBlack
        .opacity(0.22)
        .ignoresSafeArea()

      MoruDialog(
        title: "다른 루틴에서 사용 중",
        message: RoutineManagementCopy.weekdayConflictMessage(conflict),
        primaryTitle: "괜찮아요",
        secondaryTitle: "변경하기",
        primaryAction: {
          weekdayConflict = nil
        },
        secondaryAction: {
          Task {
            await resolveWeekdayConflictAndDismissIfNeeded()
          }
        }
      )
    }
  }

  private func saveAndDismissIfNeeded() async {
    saveErrorMessage = nil

    if await onSave(draft) {
      dismiss()
    } else {
      saveErrorMessage = "루틴을 저장하지 못했어요. 다시 시도해 주세요."
    }
  }

  private func resolveWeekdayConflictAndDismissIfNeeded() async {
    saveErrorMessage = nil

    if await onResolveWeekdayConflict(draft) {
      weekdayConflict = nil
      dismiss()
    } else {
      weekdayConflict = nil
      saveErrorMessage = "루틴을 저장하지 못했어요. 다시 시도해 주세요."
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .routineManagementTextStyle(.b4.weight(.semiBold))
      .foregroundStyle(MoruPilotColor.textPrimary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func editorInputRow(
    text: Binding<String>,
    placeholder: String
  ) -> some View {
    TextField(placeholder, text: text, axis: .vertical)
      .routineManagementTextStyle(.b4)
      .foregroundStyle(MoruPilotColor.textStrong)
      .tint(MoruPilotColor.accent)
      .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
      .padding(.horizontal, MoruPilotSpacing.sixteen)
      .padding(.vertical, MoruPilotSpacing.twelve)
      .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 72 : 48)
      .background(inputBackground)
  }

  private var inputBackground: some View {
    RoundedRectangle(cornerRadius: MoruPilotRadius.card)
      .fill(AppColor.grayWhite.opacity(0.4))
      .overlay(
        RoundedRectangle(cornerRadius: MoruPilotRadius.card)
          .stroke(MoruPilotColor.border, lineWidth: 1)
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
    onResolveWeekdayConflict: { _ in true }
  )
}
#endif
