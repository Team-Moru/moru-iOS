//
//  MoruWeekdaySelector.swift
//  Moru
//

import SwiftUI

/// 요일 선택기. 루틴 설정과 온보딩이 공유한다.
struct MoruWeekdaySelector: View {
  @Binding var selectedWeekdays: Set<Weekday>
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        LazyVGrid(
          columns: Array(
            repeating: GridItem(.flexible(), spacing: MoruSpacing.twelve),
            count: 4
          ),
          spacing: MoruSpacing.twelve
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
    ForEach(Weekday.displayOrder) { weekday in
      Button {
        toggle(weekday)
      } label: {
        Text(weekday.shortTitle)
          .moruTextStyle(.b4.weight(.semiBold))
          .foregroundStyle(
            selectedWeekdays.contains(weekday)
              ? AppColor.grayWhite
              : MoruColor.textPrimary
          )
          .frame(
            width: dynamicTypeSize.isAccessibilitySize ? 52 : 44,
            height: dynamicTypeSize.isAccessibilitySize ? 52 : 44
          )
          .background(
            selectedWeekdays.contains(weekday)
              ? MoruColor.accent
              : MoruColor.border
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
  MoruWeekdaySelector(
    selectedWeekdays: .constant([.monday, .wednesday, .friday])
  )
  .padding()
  .background(AppColor.babyBlue50)
}
#endif
