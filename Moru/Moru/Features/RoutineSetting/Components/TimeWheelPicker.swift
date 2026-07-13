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

  @State private var dragOffset: CGFloat = 0
  @State private var isDragging = false
  @State private var initialValue: Int = 0

  private let itemHeight: CGFloat = 72

  var body: some View {
    VStack(spacing: 0) {
      Text(String(format: "%02d", wrappedValue(value - 1, in: range)))
        .font(AppFont.pretendardBold(size: 52))
        .foregroundStyle(AppColor.moruTextPrimary.opacity(0.35))
        .frame(height: itemHeight)

      Text(String(format: "%02d", value))
        .font(AppFont.pretendardBold(size: 52))
        .foregroundStyle(AppColor.moruTextPrimary)
        .frame(height: itemHeight)

      Text(String(format: "%02d", wrappedValue(value + 1, in: range)))
        .font(AppFont.pretendardBold(size: 52))
        .foregroundStyle(AppColor.moruTextPrimary.opacity(0.35))
        .frame(height: itemHeight)
    }
    .frame(height: itemHeight * 3)
    .offset(y: dragOffset)
    .frame(width: 92, height: itemHeight)
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
