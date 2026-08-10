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
          header

          if let errorMessage = viewModel.state.errorMessage,
             viewModel.state.routines.isEmpty {
            routineErrorState(message: errorMessage)
              .padding(.top, MoruPilotSpacing.thirtyTwo)
          } else if viewModel.state.routines.isEmpty {
            emptyRoutineState
              .padding(.top, MoruPilotSpacing.thirtyTwo)
          } else {
            activeRoutineSection
              .padding(.top, MoruPilotSpacing.thirtyTwo)

            inactiveRoutineSection
              .padding(.top, AppSpacing.forty)

            addRoutineButton
              .padding(.top, MoruPilotSpacing.sixteen)
          }

          if let errorMessage = viewModel.state.errorMessage,
             !viewModel.state.routines.isEmpty {
            retainedRoutineErrorState(message: errorMessage)
              .padding(.top, AppSpacing.sm)
          }
        }
        .padding(.horizontal, MoruPilotSpacing.twenty)
        .padding(.top, MoruPilotSpacing.twenty)
        .padding(.bottom, MoruPilotSpacing.thirtySix)
      }
      .defaultScrollAnchor(.top)
      .background(MoruPilotColor.canvas.ignoresSafeArea())
      .navigationBarTitleDisplayMode(.inline)
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
      if entryPoint == .newRoutine {
        presentCreationSheet()
      }
    }
    .overlay {
      if let activationConflict {
        activationConflictDialogOverlay(activationConflict)
      }
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

  private var header: some View {
    Text("루틴")
      .routineListTextStyle(.h3)
      .foregroundStyle(AppColor.gray550)
      .fixedSize(horizontal: false, vertical: true)
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
        .foregroundStyle(MoruPilotColor.accentSoft)

      Text("아직 만든 루틴이 없어요.")
        .routineListTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)

      Text("새 루틴을 만들어 나만의 아침을 시작해 보세요.")
        .routineListTextStyle(.c1)
        .foregroundStyle(MoruPilotColor.textSecondary)
        .multilineTextAlignment(.center)

      MoruButton(
        "새 루틴 만들기",
        style: .secondary,
        componentStyle: .figmaPilot
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
        .foregroundStyle(MoruPilotColor.accentSoft)
        .accessibilityHidden(true)

      Text(message)
        .routineListTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      Text("잠시 후 다시 시도해 주세요.")
        .routineListTextStyle(.c1)
        .foregroundStyle(MoruPilotColor.textSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      MoruButton(
        "다시 불러오기",
        style: .secondary,
        componentStyle: .figmaPilot
      ) {
        viewModel.load()
      }
    }
    .frame(maxWidth: .infinity, minHeight: 320)
  }

  private func retainedRoutineErrorState(message: String) -> some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      Text(message)
        .routineListTextStyle(.c1)
        .foregroundStyle(AppColor.orange500)
        .fixedSize(horizontal: false, vertical: true)

      Button("다시 불러오기") {
        viewModel.load()
      }
      .routineListTextStyle(.c1.weight(.semiBold))
      .foregroundStyle(MoruPilotColor.accent)
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
        .routineListTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(AppColor.gray400)
        .fixedSize(horizontal: false, vertical: true)

      if routines.isEmpty {
        emptySectionCard(title: emptyTitle)
          .padding(.top, MoruPilotSpacing.sixteen)
      } else {
        VStack(spacing: MoruPilotSpacing.sixteen) {
          ForEach(routines) { routine in
            RoutineSettingCard(
              routine: routine,
              isActive: activationBinding(for: routine),
              componentStyle: .figmaPilot,
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
        .padding(.top, MoruPilotSpacing.sixteen)
      }
    }
  }

  private var addRoutineButton: some View {
    Button {
      presentCreationSheet()
    } label: {
      MoruRoutineCard(
        title: RoutineManagementCopy.addRoutine,
        isAddCard: true,
        componentStyle: .figmaPilot
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
        .routineListTextStyle(.c1)
        .foregroundStyle(MoruPilotColor.textSecondary)
    }
    .frame(maxWidth: .infinity)
    .frame(minHeight: 76)
    .padding(.vertical, AppSpacing.sm)
    .background(AppColor.grayWhite.opacity(0.35))
    .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard))
    .shadow(color: MoruPilotColor.shadow, radius: 7.5, x: 0, y: 0)
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

  private func activationConflictDialogOverlay(
    _ conflict: RoutineActivationConflictState
  ) -> some View {
    ZStack {
      AppColor.grayBlack
        .opacity(0.22)
        .ignoresSafeArea()

      MoruDialog(
        title: "다른 루틴을 끌까요?",
        message: RoutineManagementCopy.activeRoutineReplacementMessage(conflict),
        primaryTitle: "취소",
        secondaryTitle: "변경하기",
        primaryAction: {
          activationConflict = nil
          activationConflictRoutineID = nil
        },
        secondaryAction: {
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
      )
    }
  }
}

extension View {
  func routineListTextStyle(_ style: MoruTextStyle) -> some View {
    moruPilotTextStyle(style)
  }
}

#if DEBUG
#Preview {
  RoutineSettingView(dependencies: .homePreview)
}
#endif
