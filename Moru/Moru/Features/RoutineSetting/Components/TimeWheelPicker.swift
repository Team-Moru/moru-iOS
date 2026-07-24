//
//  TimeWheelPicker.swift
//  Moru
//
//  Created by Antigravity on 7/10/26.
//

import SwiftUI

struct TimeWheelPicker: View {
  @Binding var value: Int
  let range: Int

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var dragOffset: CGFloat = 0
  @State private var isDragging = false
  @State private var initialValue: Int = 0

  @ScaledMetric(relativeTo: .body) private var accessibilityItemHeight: CGFloat = 48

  var body: some View {
    VStack(spacing: 0) {
      Text(String(format: "%02d", wrappedValue(value - 1, in: range)))
        .routineManagementTextStyle(.b2.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textSecondary)
        .frame(height: itemHeight)

      Text(String(format: "%02d", value))
        .routineManagementTextStyle(.b1.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)
        .frame(height: itemHeight)

      Text(String(format: "%02d", wrappedValue(value + 1, in: range)))
        .routineManagementTextStyle(.b2.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textSecondary)
        .frame(height: itemHeight)
    }
    .frame(height: itemHeight * 3)
    .offset(y: dragOffset)
    .frame(width: 84, height: itemHeight * 3)
    .clipped()
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 4)
        .onChanged { gesture in
          if !isDragging {
            isDragging = true
            initialValue = value
          }

          let totalTranslation = gesture.translation.height
          let step = Int((totalTranslation / itemHeight).rounded())
          let remainder = totalTranslation - CGFloat(step) * itemHeight

          let newValue = wrappedValue(initialValue - step, in: range)
          if newValue != value {
            value = newValue
            triggerHapticFeedback()
          }

          dragOffset = remainder
        }
        .onEnded { _ in
          isDragging = false
          withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
            dragOffset = 0
          }
        }
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(range == 24 ? "시" : "분")
    .accessibilityValue(String(format: "%02d", value))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        value = wrappedValue(value + 1, in: range)
      case .decrement:
        value = wrappedValue(value - 1, in: range)
      @unknown default:
        break
      }
    }
  }

  private var itemHeight: CGFloat {
    dynamicTypeSize.isAccessibilitySize
      ? max(accessibilityItemHeight, 60)
      : 48
  }

  private func wrappedValue(_ value: Int, in range: Int) -> Int {
    ((value % range) + range) % range
  }

  private func triggerHapticFeedback() {
    let generator = UISelectionFeedbackGenerator()
    generator.prepare()
    generator.selectionChanged()
  }
}

#if DEBUG
#Preview {
  TimeWheelPicker(value: .constant(7), range: 24)
    .background(Color.gray.opacity(0.1))
}
#endif
