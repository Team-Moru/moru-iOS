//
//  RoutineSettingView.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct RoutineSettingView: View {
  @State private var viewModel: RoutineSettingViewModel
  @State private var editorDraft: RoutineDraftState?
  @State private var activationConflictRoutineID: UUID?
  @State private var activationConflict: RoutineWeekdayConflictState?
  @State private var activationOverrides: [UUID: Bool] = [:]
  @State private var isActivationMutationInProgress = false

  init(dependencies: DependencyContainer) {
    _viewModel = State(initialValue: RoutineSettingViewModel(dependencies: dependencies))
  }

  var body: some View {
    NavigationStack {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
          header
          activeRoutineSection
          inactiveRoutineSection
          addRoutineButton

          if let errorMessage = viewModel.state.errorMessage {
            Text(errorMessage)
              .font(AppFont.caption1Medium)
              .foregroundStyle(AppColor.orange500)
          }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.thirtySix)
      }
      .background(AppColor.babyBlue50.ignoresSafeArea())
      .navigationBarTitleDisplayMode(.inline)
    }
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
        await viewModel.saveDraft(savedDraft)
      } onResolveWeekdayConflict: { savedDraft in
        await viewModel.saveDraftResolvingWeekdayConflict(savedDraft)
      } onDelete: { routineID in
        await viewModel.deleteRoutine(id: routineID)
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
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      Text(title)
        .font(AppFont.pretendardSemiBold(size: 16))
        .foregroundStyle(AppColor.moruTextPrimary)

      if routines.isEmpty {
        emptySectionCard(title: emptyTitle)
      } else {
        ForEach(routines) { routine in
          RoutineSettingCard(
            routine: routine,
            isActive: activationBinding(for: routine),
            onTap: {
              editorDraft = viewModel.makeDraft(for: routine.id)
            }
          )
          .disabled(isMutationInProgress)
        }
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
    .disabled(isMutationInProgress)
  }

  private func emptySectionCard(title: String) -> some View {
    VStack(spacing: AppSpacing.md) {
      Text(title)
        .font(AppFont.pretendardMedium(size: 14))
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 76)
    .background(AppColor.grayWhite.opacity(0.35))
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    .shadow(color: AppColor.babyBlue150, radius: 7.5, x: 0, y: 0)
  }

  private var isMutationInProgress: Bool {
    viewModel.isMutationInProgress || isActivationMutationInProgress
  }

  private func activationBinding(for routine: RoutineSettingItemState) -> Binding<Bool> {
    Binding(
      get: {
        activationOverrides[routine.id]
          ?? viewModel.state.routines.first { $0.id == routine.id }?.isActive
          ?? routine.isActive
      },
      set: { isActive in
        routineActivationDidChange(routineID: routine.id, isActive: isActive)
      }
    )
  }

  private func routineActivationDidChange(routineID: UUID, isActive: Bool) {
    guard !isMutationInProgress else {
      return
    }

    activationOverrides[routineID] = isActive

    guard isActive else {
      performActivationMutation(routineID: routineID, isActive: false)
      return
    }

    if let conflict = viewModel.activationConflict(for: routineID) {
      activationOverrides.removeValue(forKey: routineID)
      activationConflictRoutineID = routineID
      activationConflict = conflict
    } else {
      performActivationMutation(routineID: routineID, isActive: true)
    }
  }

  private func performActivationMutation(routineID: UUID, isActive: Bool) {
    guard !isMutationInProgress else {
      return
    }

    isActivationMutationInProgress = true
    Task { @MainActor in
      _ = await viewModel.routineActivationDidChange(id: routineID, isActive: isActive)
      activationOverrides.removeValue(forKey: routineID)
      isActivationMutationInProgress = false
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
        message: "\(conflict.weekdayText)은 알림이 설정된\n다른 루틴이 이미 있어요.\n해당 루틴으로 요일을 변경하시겠어요?",
        primaryTitle: "괜찮아요",
        secondaryTitle: "변경하기",
        primaryAction: {
          guard !isMutationInProgress else {
            return
          }

          activationConflict = nil
          activationConflictRoutineID = nil
        },
        secondaryAction: {
          guard let routineID = activationConflictRoutineID,
                !isMutationInProgress else {
            return
          }

          isActivationMutationInProgress = true
          Task { @MainActor in
            _ = await viewModel.activateRoutineResolvingWeekdayConflict(id: routineID)
            activationConflict = nil
            activationConflictRoutineID = nil
            activationOverrides.removeValue(forKey: routineID)
            isActivationMutationInProgress = false
          }
        }
      )
      .disabled(isMutationInProgress)
    }
  }

}

#if DEBUG
#Preview {
  RoutineSettingView(dependencies: .homePreview)
}
#endif
