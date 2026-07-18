//
//  RoutineFinishedView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import SwiftUI
enum RoutineCompletionAccessibility {
  static let primary = "routineCompletion.primary"
  static let home = "routineCompletion.home"
  static let homeTitle = "홈으로"
  static let recordTitle = "오늘의 기록 확인"
}


enum RoutineCompletionActionConfiguration: Equatable {
  enum Destination: Equatable {
    case record
    case home
  }

  enum Style: Equatable {
    case primary
    case secondary
  }

  struct Action: Identifiable, Equatable {
    let destination: Destination
    let title: String
    let accessibilityIdentifier: String
    let accessibilityHint: String
    let style: Style

    var id: String {
      accessibilityIdentifier
    }
  }

  case trialHomeOnly
  case regularRecordAndHome

  var actions: [Action] {
    switch self {
    case .trialHomeOnly:
      return [
        Action(
          destination: .home,
          title: RoutineCompletionAccessibility.homeTitle,
          accessibilityIdentifier: RoutineCompletionAccessibility.primary,
          accessibilityHint: "홈 화면으로 돌아갑니다.",
          style: .primary
        )
      ]

    case .regularRecordAndHome:
      return [
        Action(
          destination: .record,
          title: RoutineCompletionAccessibility.recordTitle,
          accessibilityIdentifier: RoutineCompletionAccessibility.primary,
          accessibilityHint: "방금 완료한 루틴의 기록을 확인합니다.",
          style: .primary
        ),
        Action(
          destination: .home,
          title: RoutineCompletionAccessibility.homeTitle,
          accessibilityIdentifier: RoutineCompletionAccessibility.home,
          accessibilityHint: "홈 화면으로 돌아갑니다.",
          style: .secondary
        )
      ]
    }
  }
}

struct RoutineFinishedView: View {
  let routineName: String
  let completionRate: Int
  let completedStepCount: Int
  let skippedStepCount: Int
  let actionConfiguration: RoutineCompletionActionConfiguration
  let onAction: (RoutineCompletionActionConfiguration.Destination) -> Void
  let isActionDisabled: Bool

  var body: some View {
    VStack(spacing: 28) {
      Spacer()

      Text("루틴 완료")
        .font(AppFont.title2Bold)
        .foregroundStyle(AppColor.moruTextStrong)

      Text("\(completionRate)%")
        .font(.system(size: 72, weight: .bold, design: .rounded))
        .foregroundStyle(AppColor.moruTextStrong)

      VStack(spacing: 8) {
        Text(routineName)
          .font(AppFont.body1NormalSemiBold)
          .foregroundStyle(AppColor.moruTextPrimary)

        Text("완료 \(completedStepCount)개 · 건너뜀 \(skippedStepCount)개")
          .font(AppFont.body1NormalSemiBold)
          .foregroundStyle(AppColor.moruTextSecondary)
      }

      VStack(spacing: 12) {
        ForEach(actionConfiguration.actions) { action in
          Button {
            onAction(action.destination)
          } label: {
            Text(action.title)
              .font(AppFont.body1NormalSemiBold)
              .foregroundStyle(
                action.style == .primary ? AppColor.grayWhite : AppColor.babyBlue250
              )
              .frame(maxWidth: .infinity)
              .frame(height: 56)
              .background(
                action.style == .primary ? AppColor.orange350 : AppColor.grayWhite
              )
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
          .disabled(isActionDisabled)
          .accessibilityIdentifier(action.accessibilityIdentifier)
          .accessibilityLabel(action.title)
          .accessibilityHint(action.accessibilityHint)
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 20)

      Spacer()
    }
  }
}
