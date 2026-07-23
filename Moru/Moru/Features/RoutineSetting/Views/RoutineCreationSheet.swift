//
//  RoutineCreationSheet.swift
//  Moru
//

import SwiftUI

struct RoutineCreationSheet: View {
  static let choiceAccessibilityIdentifier = "routine.creation.choice"
  static let recommendedAccessibilityIdentifier =
    "routine.creation.choice.recommended"
  static let directAccessibilityIdentifier = "routine.creation.choice.direct"

  @Environment(\.dismiss) private var dismiss
  @State private var selectedMode: RoutineCreationFlowMode?

  private let dependencies: DependencyContainer
  private let directDraft: RoutineDraftState
  private let onSave: (RoutineDraftState) async -> Bool
  private let onResolveWeekdayConflict: (RoutineDraftState) async -> Bool
  private let weekdayConflictState:
    (RoutineDraftState) -> RoutineWeekdayConflictState?

  init(
    dependencies: DependencyContainer,
    directDraft: RoutineDraftState,
    initialMode: RoutineCreationFlowMode? = nil,
    onSave: @escaping (RoutineDraftState) async -> Bool,
    onResolveWeekdayConflict: @escaping (RoutineDraftState) async -> Bool,
    weekdayConflictState:
      @escaping (RoutineDraftState) -> RoutineWeekdayConflictState?
  ) {
    self.dependencies = dependencies
    self.directDraft = directDraft
    self.onSave = onSave
    self.onResolveWeekdayConflict = onResolveWeekdayConflict
    self.weekdayConflictState = weekdayConflictState
    _selectedMode = State(initialValue: initialMode)
  }

  var body: some View {
    switch selectedMode {
    case .recommendedAddition:
      recommendedCreationFlow
    case .directAddition:
      RoutineEditorView(
        draft: directDraft,
        onSave: onSave,
        onResolveWeekdayConflict: onResolveWeekdayConflict,
        weekdayConflictState: weekdayConflictState
      )
    case .onboarding:
      EmptyView()
    case nil:
      RoutineCreationModeSelectionView(
        onSelect: { mode in
          selectedMode = mode
        },
        onCancel: {
          dismiss()
        }
      )
    }
  }

  private var recommendedCreationFlow: some View {
    OnboardingFlowView(
      viewModel: OnboardingViewModel(
        flowMode: .recommendedAddition,
        routineSuggestionService: dependencies.routineSuggestionService,
        recommendedRoutineCreationUseCase:
          RecommendedRoutineCreationUseCase(
            routineRepository: dependencies.routineRepository,
            alarmScheduleMutator: dependencies.alarmScheduleMutator
          ),
        onRecommendedRoutineSaved: { _ in
          dismiss()
        },
        onCancelled: {
          dismiss()
        }
      )
    )
  }
}

private struct RoutineCreationModeSelectionView: View {
  let onSelect: (RoutineCreationFlowMode) -> Void
  let onCancel: () -> Void

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.thirtySix) {
          VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("새 루틴 만들기")
              .font(AppFont.title2Bold)
              .foregroundStyle(AppColor.moruTextStrong)
              .fixedSize(horizontal: false, vertical: true)

            Text("추천을 받거나 직접 구성할 수 있어요.")
              .font(AppFont.label1NormalMedium)
              .foregroundStyle(AppColor.moruTextSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          VStack(spacing: AppSpacing.md) {
            creationOption(
              title: "추천 루틴 만들기",
              subtitle: "경험과 목표를 바탕으로 로컬 템플릿을 추천해요.",
              icon: "sparkles",
              accessibilityIdentifier:
                RoutineCreationSheet.recommendedAccessibilityIdentifier
            ) {
              onSelect(.recommendedAddition)
            }

            creationOption(
              title: "직접 루틴 만들기",
              subtitle: "이름, 알람, 루틴 항목을 직접 설정해요.",
              icon: "square.and.pencil",
              accessibilityIdentifier:
                RoutineCreationSheet.directAccessibilityIdentifier
            ) {
              onSelect(.directAddition)
            }
          }

          Spacer(minLength: AppSpacing.thirtySix)
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.top, AppSpacing.forty)
      }
      .background(AppColor.babyBlue50.ignoresSafeArea())
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("취소", action: onCancel)
            .font(AppFont.body1NormalMedium)
            .foregroundStyle(AppColor.moruTextSecondary)
        }
      }
    }
    .accessibilityIdentifier(
      RoutineCreationSheet.choiceAccessibilityIdentifier
    )
  }

  private func creationOption(
    title: String,
    subtitle: String,
    icon: String,
    accessibilityIdentifier: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: AppSpacing.md) {
        Image(systemName: icon)
          .font(.system(size: 28, weight: .semibold))
          .foregroundStyle(AppColor.orange350)
          .frame(width: 48, height: 48)
          .background(AppColor.orange100)
          .clipShape(Circle())

        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
          Text(title)
            .font(AppFont.heading3SemiBold)
            .foregroundStyle(AppColor.moruTextStrong)
            .fixedSize(horizontal: false, vertical: true)

          Text(subtitle)
            .font(AppFont.caption1Medium)
            .foregroundStyle(AppColor.moruTextSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .layoutPriority(1)

        Spacer()

        Image(systemName: "chevron.right")
          .foregroundStyle(AppColor.moruTextSecondary)
      }
      .padding(AppSpacing.lg)
      .frame(maxWidth: .infinity, minHeight: 104)
      .background(AppColor.grayWhite)
      .overlay(
        RoundedRectangle(cornerRadius: AppRadius.lg)
          .stroke(AppColor.moruBorder, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}
