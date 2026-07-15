//
//  RoutineScheduleSettingView.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct RoutineScheduleSettingView: View {
  @Environment(\.dismiss) private var dismiss

  @Binding var hour: Int
  @Binding var minute: Int
  @Binding var selectedWeekdays: Set<Weekday>

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.none) {
      Text("루틴을 실행할\n시간을 설정해 주세요")
        .font(AppFont.heading1SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)
        .lineSpacing(4)
        .padding(.top, AppSpacing.lg)

      Spacer(minLength: AppSpacing.fortyEight)

      VStack(spacing: AppSpacing.sm) {
        Text("기상 시간")
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)

        timeDragPicker

        Text(hour < 12 ? "AM" : "PM")
          .font(AppFont.label1NormalMedium)
          .foregroundStyle(AppColor.moruTextSecondary)
      }
      .frame(maxWidth: .infinity)

      Divider()
        .background(AppColor.moruBorder)
        .padding(.vertical, AppSpacing.xxl)

      VStack(spacing: AppSpacing.md) {
        Text("반복 요일")
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)

        RoutineWeekdaySelector(selectedWeekdays: $selectedWeekdays)
      }
      .frame(maxWidth: .infinity)

      Spacer()

      Button {
        dismiss()
      } label: {
        Text("다음")
          .font(AppFont.body1NormalSemiBold)
          .foregroundStyle(AppColor.grayWhite)
          .frame(maxWidth: .infinity)
          .frame(height: 52)
          .background(selectedWeekdays.isEmpty ? AppColor.moruDisabled : AppColor.orange350)
          .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
      }
      .disabled(selectedWeekdays.isEmpty)
      .buttonStyle(.plain)
    }
    .padding(.horizontal, AppSpacing.lg)
    .padding(.top, AppSpacing.fiftySix)
    .padding(.bottom, AppSpacing.lg)
    .background(AppColor.babyBlue50.ignoresSafeArea())
  }

  private var timeDragPicker: some View {
    HStack(spacing: AppSpacing.sm) {
      TimeWheelPicker(value: $hour, range: 24)

      Text(":")
        .font(AppFont.pretendardBold(size: 52))
        .foregroundStyle(AppColor.moruTextPrimary)
        .offset(y: -2)

      TimeWheelPicker(value: $minute, range: 60)
    }
    .frame(maxWidth: .infinity)
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
