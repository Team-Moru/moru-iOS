//
//  MoruWeekdaySelector.swift
//  Moru
//

import SwiftUI

/// 요일 선택기. 루틴 설정과 온보딩이 공유한다.
///
/// 일곱 개가 나란히 놓인 세그먼트 컨트롤이라 유리를 쓴다. 유리는 다른 유리를
/// 샘플링하지 못하므로 `GlassEffectContainer`로 묶어 샘플링 영역을 공유시킨다.
/// 자세한 것은 `docs/LiquidGlassRules.md`.
struct MoruWeekdaySelector: View {
  @Binding var selectedWeekdays: Set<Weekday>
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    GlassEffectContainer(spacing: MoruSpacing.eight) {
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
      let isSelected = selectedWeekdays.contains(weekday)

      Button {
        toggle(weekday)
      } label: {
        Text(weekday.shortTitle)
          .moruTextStyle(.b4.weight(.semiBold))
          .foregroundStyle(
            isSelected ? AppColor.grayWhite : MoruColor.textPrimary
          )
          .frame(
            width: dynamicTypeSize.isAccessibilitySize ? 52 : 44,
            height: dynamicTypeSize.isAccessibilitySize ? 52 : 44
          )
      }
      .buttonStyle(.plain)
      // 선택 상태만 틴트를 얹는다. 틴트는 의미를 담을 때만 쓴다.
      .glassEffect(
        isSelected
          ? .regular.tint(MoruColor.accent).interactive()
          : .regular.interactive(),
        in: .circle
      )
      .frame(maxWidth: .infinity)
      .accessibilityLabel("\(weekday.shortTitle)요일")
      .accessibilityValue(isSelected ? "선택됨" : "선택 안 됨")
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
  .background(MoruColor.canvas)
}
#endif
