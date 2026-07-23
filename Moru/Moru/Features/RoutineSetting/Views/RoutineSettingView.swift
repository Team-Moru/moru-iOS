//
//  RoutineSettingView.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct RoutineSettingView: View {
  static let rootAccessibilityIdentifier = "routine.root"

  @State private var viewModel: RoutineSettingViewModel
  @State private var editorDraft: RoutineDraftState?
  @State private var activationConflictRoutineID: UUID?
  @State private var activationConflict: RoutineWeekdayConflictState?

  init(dependencies: DependencyContainer) {
    _viewModel = State(initialValue: RoutineSettingViewModel(dependencies: dependencies))
  }

  var body: some View {
    NavigationStack {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
          header

          activeRoutineSection
            .padding(.top, AppSpacing.xxl)

          inactiveRoutineSection
            .padding(.top, AppSpacing.forty)

          addRoutineButton
            .padding(.top, AppSpacing.sm)

          if let errorMessage = viewModel.state.errorMessage {
            Text(errorMessage)
              .font(AppFont.caption1Medium)
              .foregroundStyle(AppColor.orange500)
              .padding(.top, AppSpacing.sm)
          }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.thirtySix)
      }
      .background(AppColor.babyBlue50.ignoresSafeArea())
      .navigationBarTitleDisplayMode(.inline)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(Self.rootAccessibilityIdentifier)
    .accessibilityLabel("루틴")
    .task {
      viewModel.load()
    }
    .overlay {
      if let activationConflict {
        activationConflictDialogOverlay(activationConflict)
      }
    }
    .sheet(item: $editorDraft) { draft in
      RoutineEditorView(draft: draft) { savedDraft in
        viewModel.saveDraft(savedDraft)
      } onResolveWeekdayConflict: { savedDraft in
        viewModel.saveDraftResolvingWeekdayConflict(savedDraft)
      } onDelete: { routineID in
        viewModel.deleteRoutine(id: routineID)
      } weekdayConflictState: { draft in
        viewModel.weekdayConflict(for: draft)
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: AppSpacing.xs) {
      Text("루틴")
        .font(AppFont.pretendardSemiBold(size: 24))
        .foregroundStyle(AppColor.moruTextPrimary)
    }
  }

  private var activeRoutineSection: some View {
    routineSection(
      title: "현재 사용 중인 루틴",
      routines: viewModel.state.routines.filter(\.isActive),
      emptyTitle: "아직 사용 중인 루틴이 없어요."
    )
  }

  private var inactiveRoutineSection: some View {
    routineSection(
      title: "그 외 루틴",
      routines: viewModel.state.routines.filter { !$0.isActive },
      emptyTitle: "꺼져 있는 루틴이 없어요."
    )
  }

  private func routineSection(
    title: String,
    routines: [RoutineSettingItemState],
    emptyTitle: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(AppFont.pretendardSemiBold(size: 16))
        .foregroundStyle(AppColor.moruTextPrimary)

      if routines.isEmpty {
        emptySectionCard(title: emptyTitle)
          .padding(.top, AppSpacing.md)
      } else {
        VStack(spacing: AppSpacing.sm) {
          ForEach(routines) { routine in
            RoutineSettingCard(
              routine: routine,
              isActive: activationBinding(for: routine),
              onTap: {
                editorDraft = viewModel.makeDraft(for: routine.id)
              }
            )
          }
        }
        .padding(.top, AppSpacing.md)
      }
    }
  }

  private var addRoutineButton: some View {
    Button {
      editorDraft = viewModel.makeNewDraft()
    } label: {
      MoruRoutineCard(title: "새 루틴 추가하기", isAddCard: true)
    }
    .buttonStyle(.plain)
  }

  private func emptySectionCard(title: String) -> some View {
    VStack(spacing: AppSpacing.md) {
      Text(title)
        .font(AppFont.pretendardMedium(size: 14))
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .frame(maxWidth: .infinity)
    .frame(minHeight: 76)
    .padding(.vertical, AppSpacing.sm)
    .background(AppColor.grayWhite.opacity(0.35))
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    .shadow(color: AppColor.babyBlue150, radius: 7.5, x: 0, y: 0)
  }

  private func activationBinding(for routine: RoutineSettingItemState) -> Binding<Bool> {
    Binding(
      get: {
        viewModel.state.routines.first { $0.id == routine.id }?.isActive ?? routine.isActive
      },
      set: { isActive in
        routineActivationDidChange(routineID: routine.id, isActive: isActive)
      }
    )
  }

  private func routineActivationDidChange(routineID: UUID, isActive: Bool) {
    guard isActive else {
      viewModel.routineActivationDidChange(id: routineID, isActive: false)
      return
    }

    if let conflict = viewModel.activationConflict(for: routineID) {
      activationConflictRoutineID = routineID
      activationConflict = conflict
    } else {
      viewModel.routineActivationDidChange(id: routineID, isActive: true)
    }
  }

  private func activationConflictDialogOverlay(
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
          "해당 루틴으로 요일을 변경하시겠어요?",
        ].joined(separator: "\n"),
        primaryTitle: "괜찮아요",
        secondaryTitle: "변경하기",
        primaryAction: {
          activationConflict = nil
          activationConflictRoutineID = nil
        },
        secondaryAction: {
          if let activationConflictRoutineID {
            viewModel.activateRoutineResolvingWeekdayConflict(id: activationConflictRoutineID)
          }

          activationConflict = nil
          activationConflictRoutineID = nil
        }
      )
    }
  }
}

#if DEBUG
#Preview {
  RoutineSettingView(dependencies: .homePreview)
}
#endif
