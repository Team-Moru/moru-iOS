//
//  RoutineScheduleSettingView.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct RoutineScheduleSettingView: View {
  @Binding var hour: Int
  @Binding var minute: Int
  @Binding var selectedWeekdays: Set<Weekday>
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 28 : 24) {
      timeDragPicker

      RoutineWeekdaySelector(selectedWeekdays: $selectedWeekdays)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("루틴 알림 시간과 반복 요일")
  }

  private var timeDragPicker: some View {
    ZStack {
      RoundedRectangle(cornerRadius: MoruPilotRadius.card)
        .fill(AppColor.gray150.opacity(0.65))
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 60 : 48)

      HStack(spacing: 0) {
        TimeWheelPicker(value: $hour, range: 24)
        TimeWheelPicker(value: $minute, range: 60)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: dynamicTypeSize.isAccessibilitySize ? 180 : 144)
  }
}

#if DEBUG
#Preview {
  RoutineScheduleSettingView(
    hour: .constant(7),
    minute: .constant(0),
    selectedWeekdays: .constant([.monday, .wednesday, .friday])
  )
}
#endif
