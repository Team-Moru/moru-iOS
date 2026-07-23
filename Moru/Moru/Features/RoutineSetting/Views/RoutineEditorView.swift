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

  @State private var draft: RoutineDraftState
  @State private var isStepAddSheetPresented = false
  @State private var isScheduleSettingPresented = false
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
    onSave: @escaping (RoutineDraftState) async -> Bool,
    onResolveWeekdayConflict: @escaping (RoutineDraftState) async -> Bool,
    onDelete: ((UUID) async -> Bool)? = nil,
    weekdayConflictState: @escaping (RoutineDraftState) -> RoutineWeekdayConflictState? = { _ in nil }
  ) {
    self._draft = State(initialValue: draft)
    self.onSave = onSave
    self.onResolveWeekdayConflict = onResolveWeekdayConflict
    self.onDelete = onDelete
    self.weekdayConflictState = weekdayConflictState
  }

  var body: some View {
    NavigationStack {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: AppSpacing.thirtySix) {
          editorHeader
          titleSection
          alarmSection
          stepSection

          if let saveErrorMessage {
            Text(saveErrorMessage)
              .font(AppFont.caption1Medium)
              .foregroundStyle(AppColor.orange500)
          }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.top, AppSpacing.forty)
        .padding(.bottom, 112)
      }
      .background(AppColor.babyBlue50.ignoresSafeArea())
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
            Text("저장")
              .font(AppFont.body1NormalSemiBold)
              .foregroundStyle(AppColor.grayWhite)
              .frame(maxWidth: .infinity)
              .frame(height: 66)
              .background(draft.canSave ? AppColor.orange350 : AppColor.moruDisabled)
              .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
          }
          .disabled(!draft.canSave)
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 26)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.xs)
        .background(AppColor.babyBlue50.opacity(0.94))
      }
      .sheet(isPresented: $isStepAddSheetPresented) {
        RoutineStepAddSheet { step in
          draft.steps.append(step)
        }
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(AppColor.grayWhite)
        .presentationCornerRadius(AppRadius.lg)
      }
      .sheet(isPresented: $isStepEditSheetPresented) {
        if let index = selectedEditStepIndex, draft.steps.indices.contains(index) {
          RoutineStepAddSheet(initialStep: draft.steps[index]) { updatedStep in
            draft.steps[index] = updatedStep
          }
          .presentationDetents([.height(430)])
          .presentationDragIndicator(.hidden)
          .presentationBackground(AppColor.grayWhite)
          .presentationCornerRadius(AppRadius.lg)
        }
      }
      .fullScreenCover(isPresented: $isScheduleSettingPresented) {
        RoutineScheduleSettingView(
          hour: $draft.hour,
          minute: $draft.minute,
          selectedWeekdays: $draft.selectedWeekdays
        )
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
    ZStack {
      Text(draft.routineID == nil ? "루틴 만들기" : "루틴 수정")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)
        .frame(maxWidth: .infinity)

      HStack {
        Button {
          dismiss()
        } label: {
          Text("뒤로")
            .font(AppFont.body1NormalMedium)
            .foregroundStyle(AppColor.moruTextSecondary)
        }
        .buttonStyle(.plain)

        Spacer()

        Button {
          isDeleteDialogPresented = true
        } label: {
          Text("삭제")
            .font(AppFont.body1NormalMedium)
            .foregroundStyle(AppColor.moruTextSecondary)
        }
        .opacity(draft.routineID == nil ? 0 : 1)
        .disabled(draft.routineID == nil)
        .buttonStyle(.plain)
      }
    }
    .frame(height: 44)
  }

  private var titleSection: some View {
    VStack(alignment: .leading, spacing: AppSpacing.md) {
      sectionTitle("루틴 이름")

      VStack(spacing: AppSpacing.ten) {
        editorInputRow(text: $draft.title, placeholder: "활력 루틴")
        editorInputRow(text: $draft.summary, placeholder: "루틴 설명")
      }
    }
  }

  private var alarmSection: some View {
    VStack(alignment: .leading, spacing: AppSpacing.lg) {
      sectionTitle("루틴 알림")

      Button {
        isScheduleSettingPresented = true
      } label: {
        HStack(spacing: AppSpacing.md) {
          VStack(alignment: .leading, spacing: AppSpacing.six) {
            Text(alarmTitle)
              .font(AppFont.heading3SemiBold)
              .foregroundStyle(AppColor.moruTextPrimary)

            Text("\(draft.steps.count)개 항목 · \(totalMinutes)분")
              .font(AppFont.body1NormalMedium)
              .foregroundStyle(AppColor.moruTextSecondary)
          }

          Spacer()

          Image(systemName: "chevron.right")
            .font(.system(size: 26, weight: .regular))
            .foregroundStyle(AppColor.moruTextSecondary)
        }
        .padding(.horizontal, AppSpacing.xl)
        .frame(height: 124)
        .background(AppColor.orange150)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
      }
      .buttonStyle(.plain)
    }
  }

  private var stepSection: some View {
    VStack(alignment: .leading, spacing: AppSpacing.md) {
      HStack(alignment: .center, spacing: AppSpacing.sm) {
        sectionTitle("루틴 항목")

        Text("\(draft.steps.count)개 - 총 \(totalMinutes)분")
          .font(AppFont.body1NormalMedium)
          .foregroundStyle(AppColor.moruTextSecondary)

        Spacer()
      }

      ZStack {
        VStack(spacing: AppSpacing.md) {
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
          .shadow(color: AppColor.babyBlue150.opacity(0.7), radius: 14, x: 0, y: 4)
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
      HStack(spacing: AppSpacing.xs) {
        MoruRoutineStepControlIcon(style: .plus)
          .frame(width: 18, height: 18)

        Text("새 루틴 추가하기")
          .font(AppFont.label1NormalSemiBold)
          .foregroundStyle(AppColor.moruTextSecondary)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 52)
      .background(AppColor.grayWhite)
      .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
      .overlay(
        RoundedRectangle(cornerRadius: AppRadius.sm)
          .stroke(AppColor.moruBorder, lineWidth: 1)
      )
      .shadow(color: AppColor.babyBlue150, radius: 10, x: 0, y: 0)
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
        message: "\(conflict.weekdayText)은 알림이 설정된\n다른 루틴이 이미 있어요.\n해당 루틴으로 요일을 변경하시겠어요?",
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
      .font(AppFont.heading3SemiBold)
      .foregroundStyle(AppColor.moruTextPrimary)
  }

  private func editorInputRow(
    text: Binding<String>,
    placeholder: String
  ) -> some View {
    HStack(spacing: AppSpacing.md) {
      TextField(placeholder, text: text)
        .font(AppFont.body1NormalSemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)
        .tint(AppColor.orange350)

      Button {
        text.wrappedValue = ""
      } label: {
        Image(systemName: "minus.circle")
          .resizable()
          .scaledToFit()
          .frame(width: 22, height: 22)
          .foregroundStyle(AppColor.orange350)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, AppSpacing.md)
    .frame(height: 56)
    .background(inputBackground)
  }

  private var inputBackground: some View {
    RoundedRectangle(cornerRadius: AppRadius.md)
      .fill(AppColor.grayWhite)
      .overlay(
        RoundedRectangle(cornerRadius: AppRadius.md)
          .stroke(AppColor.moruBorder, lineWidth: 1)
      )
  }

  private var alarmTitle: String {
    "\(weekdayTitle) \(String(format: "%02d:%02d", draft.hour, draft.minute))"
  }

  private var weekdayTitle: String {
    if draft.selectedWeekdays == Set(Weekday.weekdays) {
      return "평일"
    }

    if draft.selectedWeekdays == Set(Weekday.allCases) {
      return "매일"
    }

    if draft.selectedWeekdays == Set([.saturday, .sunday]) {
      return "주말"
    }

    return draft.selectedWeekdays
      .sortedByDisplayOrder()
      .map(\.shortTitle)
      .joined(separator: " ")
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
