//
//  HomeStreakCard.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct HomeStreakCard: View {

  let streak: HomeStreakState

  struct WeekdayAccessibilityConfiguration: Equatable {
    let label: String
    let value: String
  }

  static func weekdayAccessibility(
    for weekday: HomeWeekdayState
  ) -> WeekdayAccessibilityConfiguration {
    WeekdayAccessibilityConfiguration(
      label: weekday.label,
      value: weekday.isCompleted ? "완료" : "미완료"
    )
  }

  var body: some View {
    MoruCard(
      backgroundColor: AppColor.babyBlue50,
      shadowColor: AppColor.babyBlue150,
      shadowRadius: 7.5,
      shadowY: 0
    ) {
      VStack(spacing: AppSpacing.xs) {
        MoruFireIcon(size: 32)

        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
          Text("\(streak.currentDays)")
            .font(AppFont.title3Bold)
            .foregroundStyle(AppColor.orange350)

          Text("일 연속")
            .font(AppFont.caption1SemiBold)
            .foregroundStyle(AppColor.moruTextPrimary)
        }

        HStack(spacing: AppSpacing.six) {
          ForEach(streak.weekdays) { weekday in
            let accessibility = Self.weekdayAccessibility(for: weekday)

            VStack(spacing: AppSpacing.xxs) {
              Circle()
                .fill(
                  weekday.isCompleted
                    ? AppColor.orange350
                    : AppColor.babyBlue100
                )
                .frame(width: 14, height: 14)

              Text(weekday.label)
                .font(AppFont.caption1Medium)
                .foregroundStyle(AppColor.moruTextSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibility.label)
            .accessibilityValue(accessibility.value)
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
      .frame(height: 128)
    }
  }
}

#if DEBUG
#Preview {
  HomeStreakCard(streak: .placeholder)
    .padding()
    .background(AppColor.babyBlue50)
}
#endif
