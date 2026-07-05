//
//  MoruWeekdaySelector.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruWeekdaySelector: View {
  let weekdays: [String]
  @Binding var selectedWeekdays: Set<String>

  init(
    weekdays: [String] = ["월", "화", "수", "목", "금", "토", "일"],
    selectedWeekdays: Binding<Set<String>>
  ) {
    self.weekdays = weekdays
    self._selectedWeekdays = selectedWeekdays
  }

  var body: some View {
    HStack(spacing: AppSpacing.sm) {
      ForEach(weekdays, id: \.self) { weekday in
        Button {
          toggle(weekday)
        } label: {
          Text(weekday)
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

  private func toggle(_ weekday: String) {
    if selectedWeekdays.contains(weekday) {
      selectedWeekdays.remove(weekday)
    } else {
      selectedWeekdays.insert(weekday)
    }
  }
}
