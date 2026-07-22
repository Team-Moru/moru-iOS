//
//  HomeStreakCard.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct HomeStreakCard: View {

  let streak: HomeStreakState
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  static func weekdayAccessibilityValue(isCompleted: Bool) -> String {
    isCompleted ? "완료" : "미완료"
  }

  var body: some View {
    MoruCard(
      backgroundColor: AppColor.babyBlue50,
      shadowColor: AppColor.babyBlue150,
      shadowRadius: 7.5,
      shadowY: 0
    ) {
      VStack(spacing: AppSpacing.xs) {
        MoruFireIcon(size: dynamicTypeSize.isAccessibilitySize ? 44 : 32)

        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
          Text("\(streak.currentDays)")
            .font(AppFont.title3Bold)
            .foregroundStyle(AppColor.orange350)

          Text("일 연속")
            .font(AppFont.caption1SemiBold)
            .foregroundStyle(AppColor.moruTextPrimary)
        }

        if dynamicTypeSize.isAccessibilitySize {
          LazyVGrid(
            columns: Array(
              repeating: GridItem(.flexible(), spacing: AppSpacing.sm),
              count: 4
            ),
            spacing: AppSpacing.sm
          ) {
            ForEach(streak.weekdays) { weekday in
              weekdayCell(weekday)
            }
          }
        } else {
          HStack(spacing: AppSpacing.six) {
            ForEach(streak.weekdays) { weekday in
              weekdayCell(weekday)
            }
          }
        }

        Text("최고 기록 \(streak.bestDays)일")
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)
          .padding(.horizontal, AppSpacing.sm)
          .padding(.vertical, AppSpacing.xxs)
          .background(AppColor.babyBlue100)
          .clipShape(Capsule())
      }
      .frame(maxWidth: .infinity)
      .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 264 : 128)
    }
  }

  private func weekdayCell(_ weekday: HomeWeekdayState) -> some View {
    VStack(spacing: AppSpacing.xxs) {
      Circle()
        .fill(
          weekday.isCompleted
            ? AppColor.orange350
            : AppColor.babyBlue100
        )
        .frame(
          width: dynamicTypeSize.isAccessibilitySize ? 20 : 14,
          height: dynamicTypeSize.isAccessibilitySize ? 20 : 14
        )

      Text(weekday.label)
        .font(AppFont.caption1Medium)
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(weekday.label)
    .accessibilityValue(
      Self.weekdayAccessibilityValue(isCompleted: weekday.isCompleted)
    )
  }
}

#Preview {
  HomeStreakCard(streak: .placeholder)
    .padding()
    .background(AppColor.babyBlue50)
}
