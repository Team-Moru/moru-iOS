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
    MoruCard(
      backgroundColor: AppColor.babyBlue50,
      shadowColor: AppColor.babyBlue150,
      shadowRadius: 7.5,
      shadowY: 0
    ) {
      VStack(alignment: .leading, spacing: AppSpacing.md) {
        Button(action: onTap) {
          HStack {
            Text("현재 사용 중인 루틴")
              .font(AppFont.label1NormalSemiBold)
              .foregroundStyle(AppColor.moruTextPrimary)
              .fixedSize(horizontal: false, vertical: true)

            Spacer()

            MoruChevron(color: AppColor.moruTextSecondary)
          }
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
    }
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
    .padding(AppSpacing.md)
    .background(AppColor.orange100)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
  }

  private var summaryIndicator: some View {
    Rectangle()
      .fill(AppColor.orange350)
      .frame(width: 2)
      .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 112 : 48)
  }

  @ViewBuilder
  private func routineDetails(
    _ routine: HomeRoutineState,
    stacksStatus: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: AppSpacing.xs) {
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
        .font(AppFont.caption1Medium)
        .foregroundStyle(AppColor.moruTextSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func routineTitle(_ routine: HomeRoutineState) -> some View {
    Text(routine.title)
      .font(AppFont.body1NormalSemiBold)
      .foregroundStyle(AppColor.moruTextPrimary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func routineStatus(_ routine: HomeRoutineState) -> some View {
    Text(routine.statusText)
      .font(AppFont.caption1SemiBold)
      .foregroundStyle(AppColor.orange350)
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
        .font(AppFont.pretendardSemiBold(size: 13))
        .foregroundStyle(AppColor.orange350)
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
    .padding(.vertical, AppSpacing.md)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(AppColor.moruBorder)
        .frame(height: 1)
    }
  }

  private func stepTitle(_ step: HomeRoutineStepState) -> some View {
    Text(step.title)
      .font(AppFont.body1NormalMedium)
      .foregroundStyle(AppColor.moruTextPrimary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func stepDetail(_ step: HomeRoutineStepState) -> some View {
    Text(step.detail)
      .font(AppFont.label1NormalMedium)
      .foregroundStyle(AppColor.moruTextSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: AppSpacing.md) {
      Text("오늘 사용할 루틴이 아직 없어요.")
        .font(AppFont.body1NormalSemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Text("루틴 탭에서 아침 루틴을 설정해보세요.")
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .padding(AppSpacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
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
