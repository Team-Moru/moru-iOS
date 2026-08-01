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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    Group {
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
        RoutineCreationModeSelectionView { mode in
          selectedMode = mode
        }
      }
    }
    .presentationDetents(presentationDetents)
    .presentationDragIndicator(selectedMode == nil ? .visible : .hidden)
    .presentationCornerRadius(selectedMode == nil ? 24 : 0)
  }

  private var presentationDetents: Set<PresentationDetent> {
    guard selectedMode == nil else {
      return [.large]
    }

    return [
      dynamicTypeSize.isAccessibilitySize
        ? .height(540)
        : .height(313)
    ]
  }

  private var recommendedCreationFlow: some View {
    OnboardingFlowView(
      viewModel: OnboardingViewModel(
        flowMode: .recommendedAddition,
        routineSuggestionService: dependencies.routineSuggestionService,
        routineSuggestionCoordinator:
          dependencies.routineSuggestionCoordinator,
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

struct RoutineCreationModeSelectionView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let onSelect: (RoutineCreationFlowMode) -> Void

  var body: some View {
    VStack(spacing: 0) {
      Text(RoutineManagementCopy.creationTitle)
        .routineManagementTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)
        .frame(maxWidth: .infinity)
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 76 : 55)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      Divider()
        .overlay(MoruPilotColor.border)

      ScrollView(showsIndicators: false) {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 20 : 12) {
          creationOption(
            title: RoutineManagementCopy.recommendedTitle,
            subtitle: RoutineManagementCopy.recommendedDescription,
            imageName: AppImage.moruRoutineRecommendation,
            accessibilityIdentifier:
              RoutineCreationSheet.recommendedAccessibilityIdentifier
          ) {
            onSelect(.recommendedAddition)
          }

          creationOption(
            title: RoutineManagementCopy.directTitle,
            subtitle: RoutineManagementCopy.directDescription,
            imageName: AppImage.moruRoutineDirectCreation,
            accessibilityIdentifier:
              RoutineCreationSheet.directAccessibilityIdentifier
          ) {
            onSelect(.directAddition)
          }
        }
        .padding(.horizontal, MoruPilotSpacing.twenty)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 20 : 12)
      }
    }
    .background(AppColor.grayWhite)
    .accessibilityIdentifier(
      RoutineCreationSheet.choiceAccessibilityIdentifier
    )
  }

  private func creationOption(
    title: String,
    subtitle: String,
    imageName: String,
    accessibilityIdentifier: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: MoruPilotSpacing.sixteen) {
        creationImage(imageName)

        VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
          Text(title)
            .routineManagementTextStyle(.b3.weight(.semiBold))
            .foregroundStyle(MoruPilotColor.textStrong)
            .fixedSize(horizontal: false, vertical: true)

          Text(subtitle)
            .routineManagementTextStyle(.b4)
            .foregroundStyle(MoruPilotColor.textTertiary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .layoutPriority(1)

        Spacer()

        MoruChevron(
          color: MoruPilotColor.textSecondary,
          direction: .right
        )
        .frame(width: 24, height: 44)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 172 : 110)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(accessibilityIdentifier)
  }

  private func creationImage(_ imageName: String) -> some View {
    let layoutSize: CGFloat = dynamicTypeSize.isAccessibilitySize ? 76 : 64
    let renderedSize = imageName == AppImage.moruRoutineRecommendation
      ? layoutSize * 1.72
      : layoutSize

    return Image(imageName)
      .resizable()
      .scaledToFit()
      .frame(width: renderedSize, height: renderedSize)
      .frame(width: layoutSize, height: layoutSize)
      .accessibilityHidden(true)
  }
}
