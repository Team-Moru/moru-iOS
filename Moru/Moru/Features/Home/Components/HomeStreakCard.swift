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
    VStack(spacing: 0) {
      Image(AppIcon.moruHomeFireIcon)
        .resizable()
        .scaledToFit()
        .frame(
          width: dynamicTypeSize.isAccessibilitySize ? 64 : 42,
          height: dynamicTypeSize.isAccessibilitySize ? 64 : 42
        )
        .accessibilityHidden(true)

      HStack(alignment: .firstTextBaseline, spacing: MoruSpacing.four) {
        Text("\(streak.currentDays)")
          .moruTextStyle(.h2)
          .foregroundStyle(MoruColor.accent)

        Text("일 연속")
          .moruTextStyle(.c1.weight(.semiBold))
          .foregroundStyle(MoruColor.textPrimary)
      }

      if dynamicTypeSize.isAccessibilitySize {
        LazyVGrid(
          columns: Array(
            repeating: GridItem(.flexible(), spacing: MoruSpacing.eight),
            count: 4
          ),
          spacing: MoruSpacing.eight
        ) {
          ForEach(streak.weekdays) { weekday in
            weekdayCell(weekday)
          }
        }
        .padding(.top, MoruSpacing.eight)
      } else {
        HStack(spacing: MoruSpacing.eight) {
          ForEach(streak.weekdays) { weekday in
            weekdayCell(weekday)
          }
        }
        .padding(.top, MoruSpacing.four)
      }

      Text("최고 기록 \(streak.bestDays)일")
        .moruTextStyle(.c2)
        .foregroundStyle(MoruColor.textSecondary)
        .padding(.horizontal, MoruSpacing.sixteen)
        .frame(minHeight: 22)
        .background(AppColor.babyBlue100)
        .clipShape(Capsule())
        .padding(.top, MoruSpacing.eight)
    }
    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 20 : 16)
    .padding(.horizontal, MoruSpacing.sixteen)
    .frame(maxWidth: .infinity)
    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 304 : 184)
    .homePilotSurface()
  }

  private func weekdayCell(_ weekday: HomeWeekdayState) -> some View {
    VStack(spacing: MoruSpacing.four) {
      ZStack {
        Circle()
          .fill(
            weekday.isCompleted
              ? MoruColor.accent
              : AppColor.babyBlue150
          )

        if weekday.isCompleted {
          Image(systemName: "checkmark")
            .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 9 : 6, weight: .bold))
            .foregroundStyle(AppColor.grayWhite)
            .accessibilityHidden(true)
        }
      }
      .frame(
        width: dynamicTypeSize.isAccessibilitySize ? 24 : 12,
        height: dynamicTypeSize.isAccessibilitySize ? 24 : 12
      )

      Text(weekday.label)
        .moruTextStyle(.c2.weight(.regular))
        .foregroundStyle(MoruColor.textTertiary)
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
