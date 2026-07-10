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

            Spacer()

            MoruChevron(color: AppColor.moruTextSecondary)
          }
        }
        .buttonStyle(.plain)

        if let routine {
          routineSummary(routine)

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
    HStack(spacing: AppSpacing.md) {
      Rectangle()
        .fill(AppColor.orange350)
        .frame(width: 2)

      VStack(alignment: .leading, spacing: AppSpacing.xs) {
        HStack(spacing: AppSpacing.sm) {
          Text(routine.title)
            .font(AppFont.body1NormalSemiBold)
            .foregroundStyle(AppColor.moruTextPrimary)

          Text(routine.statusText)
            .font(AppFont.caption1SemiBold)
            .foregroundStyle(AppColor.orange350)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background(AppColor.grayWhite)
            .clipShape(Capsule())
        }

        Text(routine.estimatedDurationText)
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)
      }

      Spacer()

      ZStack {
        Circle()
          .stroke(AppColor.orange150, lineWidth: 3)
          .frame(width: 48, height: 48)

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
          .frame(width: 48, height: 48)

        Text(routine.progressText)
          .font(AppFont.pretendardSemiBold(size: 13))
          .foregroundStyle(AppColor.orange350)
      }
    }
    .padding(AppSpacing.md)
    .background(AppColor.orange100)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
  }

  private func routineStepRow(_ step: HomeRoutineStepState) -> some View {
    HStack(spacing: AppSpacing.sm) {
      MoruCheckBadge(state: step.isCompleted ? .on : .off)

      Text(step.title)
        .font(AppFont.body1NormalMedium)
        .foregroundStyle(AppColor.moruTextPrimary)

      Spacer()

      Text(step.detail)
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .padding(.vertical, AppSpacing.md)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(AppColor.moruBorder)
        .frame(height: 1)
    }
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
