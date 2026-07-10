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

  var body: some View {
    HStack(spacing: AppSpacing.sm) {
      ForEach(weekdays) { weekday in
        Button {
          toggle(weekday)
        } label: {
          Text(weekday.shortTitle)
            .font(AppFont.pretendardSemiBold(size: 16))
            .foregroundStyle(
              selectedWeekdays.contains(weekday) ? AppColor.grayWhite : AppColor.moruDisabled
            )
            .frame(width: 40, height: 40)
            .background(
              selectedWeekdays.contains(weekday) ? AppColor.orange350 : AppColor.grayWhite
            )
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }
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
