//
//  CurrentRoutineCard.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct CurrentRoutineCard: View {
  let routine: HomeRoutineState?
  let onTap: () -> Void
  let onStart: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.twelve) {
      Button(action: onTap) {
        HStack {
          Text(HomeCopy.currentRoutine)
            .homeFigmaTextStyle(.c1.weight(.semiBold))
            .foregroundStyle(MoruPilotColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

          Spacer()

          MoruChevron(color: MoruPilotColor.textPrimary)
        }
        .frame(minHeight: 22)
      }
      .buttonStyle(.plain)

      if let routine {
        Button(action: onStart) {
          routineSummary(routine)
        }
        .buttonStyle(.plain)

        VStack(spacing: AppSpacing.none) {
          ForEach(routine.steps) { step in
            routineStepRow(step)
          }
        }
      } else {
        emptyState
      }
    }
    .padding(.horizontal, MoruPilotSpacing.twenty)
    .padding(.vertical, MoruPilotSpacing.sixteen)
    .frame(maxWidth: .infinity, alignment: .leading)
    .homePilotSurface()
  }

  private func routineSummary(_ routine: HomeRoutineState) -> some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
          HStack(alignment: .top, spacing: AppSpacing.md) {
            summaryIndicator
            routineDetails(routine, stacksStatus: true)
          }

          progressRing(routine)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      } else {
        HStack(spacing: AppSpacing.md) {
          summaryIndicator
          routineDetails(routine, stacksStatus: false)
          Spacer()
          progressRing(routine)
        }
      }
    }
    .padding(.horizontal, MoruPilotSpacing.sixteen)
    .padding(.vertical, MoruPilotSpacing.twelve)
    .frame(minHeight: 72)
    .background(MoruPilotColor.accentSurface)
    .clipShape(RoundedRectangle(cornerRadius: MoruPilotSpacing.sixteen))
  }

  private var summaryIndicator: some View {
    Rectangle()
      .fill(AppColor.orange350)
      .frame(width: 2)
      .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 112 : 41)
  }

  @ViewBuilder
  private func routineDetails(
    _ routine: HomeRoutineState,
    stacksStatus: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if stacksStatus {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
          routineTitle(routine)
          routineStatus(routine)
        }
      } else {
        HStack(spacing: AppSpacing.sm) {
          routineTitle(routine)
          routineStatus(routine)
        }
      }

      Text(routine.estimatedDurationText)
        .homeFigmaTextStyle(.c2)
        .foregroundStyle(MoruPilotColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func routineTitle(_ routine: HomeRoutineState) -> some View {
    Text(routine.title)
      .homeFigmaTextStyle(.b4.weight(.semiBold))
      .foregroundStyle(MoruPilotColor.textPrimary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func routineStatus(_ routine: HomeRoutineState) -> some View {
    Text(routine.statusText)
      .homeFigmaTextStyle(.c2)
      .foregroundStyle(MoruPilotColor.accent)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, AppSpacing.sm)
      .padding(.vertical, AppSpacing.xxs)
      .background(AppColor.grayWhite)
      .clipShape(Capsule())
  }

  private func progressRing(_ routine: HomeRoutineState) -> some View {
    ZStack {
      Circle()
        .stroke(AppColor.orange150, lineWidth: 3)
        .frame(width: progressRingSize, height: progressRingSize)

      Circle()
        .trim(from: 0, to: routine.progress)
        .stroke(
          LinearGradient(
            stops: [
              Gradient.Stop(color: AppColor.orange200, location: 0.00),
              Gradient.Stop(color: AppColor.orange350, location: 1.00),
            ],
            startPoint: UnitPoint(x: 0.57, y: -0.06),
            endPoint: UnitPoint(x: 1, y: 0.25)
          ),
          style: StrokeStyle(lineWidth: 3, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .frame(width: progressRingSize, height: progressRingSize)

      Text(routine.progressText)
        .homeFigmaTextStyle(.c1.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.accent)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("루틴 진행률")
    .accessibilityValue(routine.progressText)
  }

  private var progressRingSize: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 96 : 48
  }

  @ViewBuilder
  private func routineStepRow(_ step: HomeRoutineStepState) -> some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
          HStack(alignment: .top, spacing: AppSpacing.sm) {
            MoruCheckBadge(state: step.isCompleted ? .on : .off)
            stepTitle(step)
          }

          stepDetail(step)
            .padding(.leading, 28)
        }
      } else {
        HStack(spacing: AppSpacing.sm) {
          MoruCheckBadge(state: step.isCompleted ? .on : .off)
          stepTitle(step)
          Spacer()
          stepDetail(step)
        }
      }
    }
    .padding(.vertical, MoruPilotSpacing.twelve)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(AppColor.moruBorder)
        .frame(height: 1)
    }
  }

  private func stepTitle(_ step: HomeRoutineStepState) -> some View {
    Text(step.title)
      .homeFigmaTextStyle(.c1)
      .foregroundStyle(MoruPilotColor.textPrimary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func stepDetail(_ step: HomeRoutineStepState) -> some View {
    Text(step.detail)
      .homeFigmaTextStyle(.c2)
      .foregroundStyle(MoruPilotColor.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.twelve) {
      Text("오늘 사용할 루틴이 아직 없어요.")
        .homeFigmaTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textPrimary)

      Text("루틴 탭에서 아침 루틴을 설정해보세요.")
        .homeFigmaTextStyle(.c1)
        .foregroundStyle(MoruPilotColor.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

#Preview {
  CurrentRoutineCard(
    routine: .placeholder,
    onTap: {},
    onStart: {}
  )
  .padding()
  .background(AppColor.babyBlue50)
}
