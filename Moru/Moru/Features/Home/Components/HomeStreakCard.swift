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

      HStack(alignment: .firstTextBaseline, spacing: MoruPilotSpacing.four) {
        Text("\(streak.currentDays)")
          .homeFigmaTextStyle(.h2)
          .foregroundStyle(MoruPilotColor.accent)

        Text("일 연속")
          .homeFigmaTextStyle(.c1.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textPrimary)
      }

      if dynamicTypeSize.isAccessibilitySize {
        LazyVGrid(
          columns: Array(
            repeating: GridItem(.flexible(), spacing: MoruPilotSpacing.eight),
            count: 4
          ),
          spacing: MoruPilotSpacing.eight
        ) {
          ForEach(streak.weekdays) { weekday in
            weekdayCell(weekday)
          }
        }
        .padding(.top, MoruPilotSpacing.eight)
      } else {
        HStack(spacing: MoruPilotSpacing.eight) {
          ForEach(streak.weekdays) { weekday in
            weekdayCell(weekday)
          }
        }
        .padding(.top, MoruPilotSpacing.four)
      }

      Text("최고 기록 \(streak.bestDays)일")
        .homeFigmaTextStyle(.c2)
        .foregroundStyle(MoruPilotColor.textSecondary)
        .padding(.horizontal, MoruPilotSpacing.sixteen)
        .frame(minHeight: 22)
        .background(AppColor.babyBlue100)
        .clipShape(Capsule())
        .padding(.top, MoruPilotSpacing.eight)
    }
    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 20 : 16)
    .padding(.horizontal, MoruPilotSpacing.sixteen)
    .frame(maxWidth: .infinity)
    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 304 : 184)
    .homePilotSurface()
  }

  private func weekdayCell(_ weekday: HomeWeekdayState) -> some View {
    VStack(spacing: MoruPilotSpacing.four) {
      ZStack {
        Circle()
          .fill(
            weekday.isCompleted
              ? MoruPilotColor.accent
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
        .homeFigmaTextStyle(.c2.weight(.regular))
        .foregroundStyle(MoruPilotColor.textTertiary)
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
