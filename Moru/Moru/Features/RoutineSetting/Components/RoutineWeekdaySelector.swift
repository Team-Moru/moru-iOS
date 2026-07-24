//
//  RoutineWeekdaySelector.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct RoutineWeekdaySelector: View {
  private let weekdays: [Weekday] = [
    .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
  ]

  @Binding var selectedWeekdays: Set<Weekday>
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        LazyVGrid(
          columns: Array(
            repeating: GridItem(.flexible(), spacing: MoruPilotSpacing.twelve),
            count: 4
          ),
          spacing: MoruPilotSpacing.twelve
        ) {
          weekdayButtons
        }
      } else {
        HStack(spacing: 0) {
          weekdayButtons
        }
        .frame(maxWidth: .infinity)
      }
    }
  }

  @ViewBuilder
  private var weekdayButtons: some View {
    ForEach(weekdays) { weekday in
      Button {
        toggle(weekday)
      } label: {
        Text(weekday.shortTitle)
          .routineManagementTextStyle(.b4.weight(.semiBold))
          .foregroundStyle(
            selectedWeekdays.contains(weekday)
              ? AppColor.grayWhite
              : AppColor.moruDisabled
          )
          .frame(
            width: dynamicTypeSize.isAccessibilitySize ? 52 : 40,
            height: dynamicTypeSize.isAccessibilitySize ? 52 : 40
          )
          .background(
            selectedWeekdays.contains(weekday)
              ? MoruPilotColor.accent
              : AppColor.gray150.opacity(0.55)
          )
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)
      .accessibilityLabel("\(weekday.shortTitle)요일")
      .accessibilityValue(
        selectedWeekdays.contains(weekday) ? "선택됨" : "선택 안 됨"
      )
    }
  }

  private func toggle(_ weekday: Weekday) {
    if selectedWeekdays.contains(weekday) {
      selectedWeekdays.remove(weekday)
    } else {
      selectedWeekdays.insert(weekday)
    }
  }
}

#if DEBUG
#Preview {
  RoutineWeekdaySelector(
    selectedWeekdays: .constant([.monday, .wednesday, .friday])
  )
  .padding()
  .background(AppColor.babyBlue50)
}
#endif
