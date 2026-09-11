//
//  RoutineSettingView.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct RoutineSettingView: View {
  static let rootAccessibilityIdentifier = "routine.root"
  static let emptyCreateRoutineAccessibilityIdentifier =
    "routine.empty.create-routine"
  static let addRoutineAccessibilityIdentifier = "routine.add"

  @State private var viewModel: RoutineSettingViewModel
  @State private var editorDraft: RoutineDraftState?
  @State private var creationDraft: RoutineDraftState?
  @State private var didHandleEntryPoint = false
  @State private var activationConflictRoutineID: UUID?
  @State private var activationConflict: RoutineActivationConflictState?

  private let entryPoint: RoutineSettingEntryPoint
  private let dependencies: DependencyContainer

  init(
    dependencies: DependencyContainer,
    entryPoint: RoutineSettingEntryPoint = .list
  ) {
    self.entryPoint = entryPoint
    self.dependencies = dependencies
    _viewModel = State(initialValue: RoutineSettingViewModel(dependencies: dependencies))
  }

  var body: some View {
    NavigationStack {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
          if let errorMessage = viewModel.state.errorMessage,
             viewModel.state.routines.isEmpty {
            routineErrorState(message: errorMessage)
              .padding(.top, MoruSpacing.thirtyTwo)
          } else if viewModel.state.routines.isEmpty {
            emptyRoutineState
              .padding(.top, MoruSpacing.thirtyTwo)
          } else {
            activeRoutineSection
              .padding(.top, MoruSpacing.thirtyTwo)

            inactiveRoutineSection
              .padding(.top, AppSpacing.forty)

            addRoutineButton
              .padding(.top, MoruSpacing.sixteen)
          }

          if let errorMessage = viewModel.state.errorMessage,
             !viewModel.state.routines.isEmpty {
            retainedRoutineErrorState(message: errorMessage)
              .padding(.top, AppSpacing.sm)
          }
        }
        .padding(.horizontal, MoruSpacing.gutter)
        .padding(.top, MoruSpacing.twenty)
      }
      .defaultScrollAnchor(.top)
      .background(MoruColor.canvas.ignoresSafeArea())
      .navigationTitle("루틴")
      .navigationBarTitleDisplayMode(.large)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(Self.rootAccessibilityIdentifier)
    .accessibilityLabel("루틴")
    .task {
      viewModel.load()

      guard !didHandleEntryPoint else {
        return
      }

      didHandleEntryPoint = true
      switch entryPoint {
      case .list:
        break
      case .newRoutine:
        presentCreationSheet()
      case .editRoutine:
        // 목록에 없는 루틴이면 초안이 비어 편집기를 열지 않고 목록에 머문다.
        editorDraft = viewModel.initialDraft(for: entryPoint)
      }
    }
    .alert(
      "다른 루틴을 끌까요?",
      isPresented: Binding(
        get: { activationConflict != nil },
        set: { isPresented in
          if !isPresented {
            activationConflict = nil
            activationConflictRoutineID = nil
          }
        }
      ),
      presenting: activationConflict
    ) { _ in
      Button("취소", role: .cancel) {
        activationConflict = nil
        activationConflictRoutineID = nil
      }
      Button("변경하기") {
        if let activationConflictRoutineID {
          Task {
            await viewModel.activateRoutineReplacingActiveRoutine(
              id: activationConflictRoutineID
            )
          }
        }

        activationConflict = nil
        activationConflictRoutineID = nil
      }
    } message: { conflict in
      Text(RoutineManagementCopy.activeRoutineReplacementMessage(conflict))
    }
    .sheet(item: $editorDraft) { draft in
      RoutineEditorView(draft: draft) { savedDraft in
        await viewModel.saveDraft(savedDraft)
      } onReplaceActiveRoutine: { savedDraft in
        await viewModel.saveDraftReplacingActiveRoutine(savedDraft)
      } onDelete: { routineID in
        await viewModel.deleteRoutine(id: routineID)
      } activeRoutineConflictState: { draft in
        viewModel.activeRoutineConflict(for: draft)
      }
    }
    .sheet(
      item: $creationDraft,
      onDismiss: viewModel.load
    ) { directDraft in
      RoutineCreationSheet(
        dependencies: dependencies,
        directDraft: directDraft
      ) { savedDraft in
        await viewModel.saveDraft(savedDraft)
      } onReplaceActiveRoutine: { savedDraft in
        await viewModel.saveDraftReplacingActiveRoutine(savedDraft)
      } activeRoutineConflictState: { draft in
        viewModel.activeRoutineConflict(for: draft)
      }
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

  private var emptyRoutineState: some View {
    VStack(spacing: AppSpacing.md) {
      Image(systemName: "checklist")
        .font(AppFont.title1SemiBold)
        .foregroundStyle(MoruColor.accentSoft)

      Text("아직 만든 루틴이 없어요.")
        .moruTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruColor.textStrong)

      Text("새 루틴을 만들어 나만의 아침을 시작해 보세요.")
        .moruTextStyle(.c1)
        .foregroundStyle(MoruColor.textSecondary)
        .multilineTextAlignment(.center)

      MoruButton(
        "새 루틴 만들기",
        style: .secondary
      ) {
        presentCreationSheet()
      }
      .accessibilityIdentifier(
        Self.emptyCreateRoutineAccessibilityIdentifier
      )
    }
    .frame(maxWidth: .infinity, minHeight: 320)
  }

  private func routineErrorState(message: String) -> some View {
    VStack(spacing: AppSpacing.md) {
      Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
        .font(AppFont.title1SemiBold)
        .foregroundStyle(MoruColor.accentSoft)
        .accessibilityHidden(true)

      Text(message)
        .moruTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruColor.textStrong)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      Text("잠시 후 다시 시도해 주세요.")
        .moruTextStyle(.c1)
        .foregroundStyle(MoruColor.textSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      MoruButton(
        "다시 불러오기",
        style: .secondary
      ) {
        viewModel.load()
      }
    }
    .frame(maxWidth: .infinity, minHeight: 320)
  }

  private func retainedRoutineErrorState(message: String) -> some View {
    VStack(alignment: .leading, spacing: MoruSpacing.eight) {
      Text(message)
        .moruTextStyle(.c1)
        .foregroundStyle(AppColor.orange500)
        .fixedSize(horizontal: false, vertical: true)

      Button("다시 불러오기") {
        viewModel.load()
      }
      .moruTextStyle(.c1.weight(.semiBold))
      .foregroundStyle(MoruColor.accent)
      .buttonStyle(.plain)
      .accessibilityHint("루틴 목록을 다시 불러옵니다.")
    }
  }

  private func routineSection(
    title: String,
    routines: [RoutineSettingItemState],
    emptyTitle: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .moruTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(AppColor.gray400)
        .fixedSize(horizontal: false, vertical: true)

      if routines.isEmpty {
        emptySectionCard(title: emptyTitle)
          .padding(.top, MoruSpacing.sixteen)
      } else {
        VStack(spacing: MoruSpacing.sixteen) {
          ForEach(routines) { routine in
            RoutineSettingCard(
              routine: routine,
              isActive: activationBinding(for: routine),
              onTap: {
                editorDraft = viewModel.makeDraft(for: routine.id)
              },
              onRetryAlarm: {
                Task {
                  await viewModel.retryAlarmScheduling(id: routine.id)
                }
              }
            )
          }
        }
        .padding(.top, MoruSpacing.sixteen)
      }
    }
  }

  private var addRoutineButton: some View {
    Button {
      presentCreationSheet()
    } label: {
      MoruRoutineCard(
        title: RoutineManagementCopy.addRoutine,
        isAddCard: true
      )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(Self.addRoutineAccessibilityIdentifier)
  }

  private func presentCreationSheet() {
    guard creationDraft == nil else {
      return
    }

    creationDraft = viewModel.makeNewDraft()
  }

  private func emptySectionCard(title: String) -> some View {
    VStack(spacing: AppSpacing.md) {
      Text(title)
        .moruTextStyle(.c1)
        .foregroundStyle(MoruColor.textSecondary)
    }
    .frame(maxWidth: .infinity)
    .frame(minHeight: 76)
    .padding(.vertical, AppSpacing.sm)
    .background(AppColor.grayWhite.opacity(0.35))
    .clipShape(RoundedRectangle(cornerRadius: MoruRadius.largeCard))
    .shadow(color: MoruColor.shadow, radius: 7.5, x: 0, y: 0)
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
      Task {
        await viewModel.routineActivationDidChange(id: routineID, isActive: false)
      }
      return
    }

    if let conflict = viewModel.activeRoutineConflict(forActivationOf: routineID) {
      activationConflictRoutineID = routineID
      activationConflict = conflict
    } else {
      Task {
        await viewModel.routineActivationDidChange(id: routineID, isActive: true)
      }
    }
  }

}

#if DEBUG
#Preview {
  RoutineSettingView(dependencies: .homePreview)
}
#endif
