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
  @State private var activationConflict: RoutineWeekdayConflictState?

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

          if viewModel.state.routines.isEmpty {
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

          if let errorMessage = viewModel.state.errorMessage {
            Text(errorMessage)
              .font(AppFont.caption1Medium)
              .foregroundStyle(AppColor.orange500)
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
      } onResolveWeekdayConflict: { savedDraft in
        await viewModel.saveDraftResolvingWeekdayConflict(savedDraft)
      } onDelete: { routineID in
        await viewModel.deleteRoutine(id: routineID)
      } weekdayConflictState: { draft in
        viewModel.weekdayConflict(for: draft)
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
      } onResolveWeekdayConflict: { savedDraft in
        await viewModel.saveDraftResolvingWeekdayConflict(savedDraft)
      } weekdayConflictState: { draft in
        viewModel.weekdayConflict(for: draft)
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
        title: "새 루틴 추가하기",
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

    if let conflict = viewModel.activationConflict(for: routineID) {
      activationConflictRoutineID = routineID
      activationConflict = conflict
    } else {
      Task {
        await viewModel.routineActivationDidChange(id: routineID, isActive: true)
      }
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
            Task {
              await viewModel.activateRoutineResolvingWeekdayConflict(
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

private struct RoutineListTextStyleModifier: ViewModifier {
  let style: MoruTextStyle

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @ViewBuilder
  func body(content: Content) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      content.font(
        .custom(
          style.weight.rawValue,
          size: style.fontSize,
          relativeTo: style.relativeTextStyle
        )
      )
    } else {
      content.moruTextStyle(style)
    }
  }
}

extension View {
  func routineListTextStyle(_ style: MoruTextStyle) -> some View {
    modifier(RoutineListTextStyleModifier(style: style))
  }
}

#if DEBUG
#Preview {
  RoutineSettingView(dependencies: .homePreview)
}
#endif
