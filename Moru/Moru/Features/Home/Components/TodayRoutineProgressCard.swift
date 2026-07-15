//
//  TodayRoutineProgressCard.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct TodayRoutineProgressCard: View {
  let progress: HomeProgressState

  var body: some View {
    MoruCard(
      backgroundColor: AppColor.babyBlue50,
      shadowColor: AppColor.babyBlue150,
      shadowRadius: 7.5,
      shadowY: 0
    ) {
      VStack(spacing: AppSpacing.sm) {
        ZStack {
          Circle()
            .stroke(AppColor.orange150, lineWidth: 8)
            .frame(width: 88, height: 88)

          Circle()
            .trim(from: 0, to: progress.progress)
            .stroke(
              progressGradient,
              style: StrokeStyle(lineWidth: 8, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .frame(width: 88, height: 88)

          VStack(spacing: AppSpacing.xxs) {
            Text(progress.percentText)
              .font(AppFont.title3SemiBold)
              .foregroundStyle(AppColor.moruTextPrimary)

            Text(progress.completedText)
              .font(AppFont.caption1Medium)
              .foregroundStyle(AppColor.moruTextSecondary)
          }
        }

        Text("오늘의 루틴")
          .font(AppFont.label1NormalSemiBold)
          .foregroundStyle(AppColor.moruTextSecondary)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 128)
    }
  }

  private var progressGradient: LinearGradient {
    LinearGradient(
      stops: [
        Gradient.Stop(color: AppColor.orange350.opacity(0.3), location: 0),
        Gradient.Stop(color: AppColor.orange350, location: 1),
      ],
      startPoint: UnitPoint(x: 0.95, y: 0.34),
      endPoint: UnitPoint(x: 0.05, y: 0.66)
    )
  }
}

#Preview {
  TodayRoutineProgressCard(progress: .placeholder)
    .padding()
    .background(AppColor.babyBlue50)
}
