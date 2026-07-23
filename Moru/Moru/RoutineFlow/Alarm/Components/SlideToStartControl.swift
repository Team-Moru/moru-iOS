//
//  SlideToStartControl.swift
//  Moru
//
//  Created by 김승겸 on 7/7/26.
//

import SwiftUI

struct SlideToStartControl: View {
  let isEnabled: Bool
  let onCompleted: () -> Void

  @State private var dragOffset: CGFloat = 0
  @State private var didComplete = false

  private let height: CGFloat = 78
  private let knobSize: CGFloat = 64
  private let horizontalPadding: CGFloat = 8

  init(
    isEnabled: Bool = true,
    onCompleted: @escaping () -> Void
  ) {
    self.isEnabled = isEnabled
    self.onCompleted = onCompleted
  }

  var body: some View {
    GeometryReader { proxy in
      let maxOffset = max(
        proxy.size.width - knobSize - horizontalPadding * 2,
        0
      )
      let completionThreshold = maxOffset * 0.82

      ZStack(alignment: .leading) {
        Capsule()
          .fill(AppColor.grayWhite.opacity(0.12))
          .background(.ultraThinMaterial, in: Capsule())
          .overlay {
            Capsule()
              .stroke(AppColor.grayWhite.opacity(0.55), lineWidth: 1)
          }

        HStack(spacing: 8) {
          Spacer()

          Text("밀어서 시작하기")
            .font(AppFont.body1NormalSemiBold)
            .foregroundStyle(AppColor.grayWhite)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

          Image(systemName: "arrow.right")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppColor.grayWhite)

          Spacer()
        }

        Circle()
          .fill(AppColor.grayWhite)
          .frame(width: knobSize, height: knobSize)
          .padding(.leading, horizontalPadding)
          .offset(x: dragOffset)
          .gesture(
            DragGesture()
              .onChanged { value in
                guard isEnabled, !didComplete else {
                  return
                }
                dragOffset = min(max(value.translation.width, 0), maxOffset)
              }
              .onEnded { _ in
                guard isEnabled, !didComplete else {
                  return
                }

                if dragOffset >= completionThreshold {
                  completeSlide(maxOffset: maxOffset)
                } else {
                  withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    dragOffset = 0
                  }
                }
              }
          )
      }
      .opacity(isEnabled ? 1 : 0.6)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("루틴 시작하기")
      .accessibilityHint("두 번 탭하면 오늘의 루틴을 시작합니다.")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction(.default) {
        guard isEnabled else {
          return
        }
        completeSlide(maxOffset: maxOffset)
      }
    }
    .frame(height: height)
  }

  private func completeSlide(maxOffset: CGFloat) {
    guard isEnabled, !didComplete else {
      return
    }

    didComplete = true
    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
      dragOffset = maxOffset
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      onCompleted()
    }
  }
}
