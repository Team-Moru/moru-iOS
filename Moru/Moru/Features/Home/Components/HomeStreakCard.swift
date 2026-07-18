//
//  HomeStreakCard.swift
//  Moru
//

import SwiftUI

struct HomeStreakCard: View {

  let streak: HomeStreakState
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        MoruFireIcon(size: flameIconSize)

        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
          Text("\(streak.currentDays)")
            .font(AppFont.title3Bold)
            .foregroundStyle(AppColor.orange350)

          Text("일 연속")
            .font(AppFont.caption1SemiBold)
            .foregroundStyle(AppColor.moruTextPrimary)
        }

        ViewThatFits(in: .horizontal) {
          HStack(spacing: AppSpacing.six) {
            ForEach(streak.weekdays) { weekday in
              weekdayCell(weekday)
            }
          }
          .fixedSize(horizontal: true, vertical: false)

          LazyVGrid(
            columns: Array(
              repeating: GridItem(.flexible(), spacing: AppSpacing.six),
              count: 4
            ),
            spacing: AppSpacing.xs
          ) {
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
      .frame(
        minHeight: cardMinimumHeight,
        maxHeight: dynamicTypeSize.isAccessibilitySize ? nil : cardMinimumHeight
      )
    }
  }
  private func weekdayCell(_ weekday: HomeWeekdayState) -> some View {
    let accessibility = Self.weekdayAccessibility(for: weekday)

    return VStack(spacing: AppSpacing.xxs) {
      Circle()
        .fill(
          weekday.isCompleted
            ? AppColor.orange350
            : AppColor.babyBlue100
        )
        .frame(width: weekdayMarkerSize, height: weekdayMarkerSize)

      Text(weekday.label)
        .font(AppFont.caption1Medium)
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibility.label)
    .accessibilityValue(accessibility.value)
  }

  private var flameIconSize: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 44 : 32
  }

  private var weekdayMarkerSize: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 20 : 14
  }

  private var cardMinimumHeight: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 208 : 128
  }
}

#if DEBUG
#Preview {
  HomeStreakCard(streak: .placeholder)
    .padding()
    .background(AppColor.babyBlue50)
}
#endif
