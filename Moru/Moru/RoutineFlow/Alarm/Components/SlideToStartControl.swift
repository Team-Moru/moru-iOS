//
//  SlideToStartControl.swift
//  Moru
//
//  Created by 김승겸 on 7/7/26.
//

import SwiftUI

struct SlideToStartControl: View {
    let onCompleted: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var didComplete = false

    private let height: CGFloat = 78
    private let knobSize: CGFloat = 64
    private let horizontalPadding: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let maxOffset = max(proxy.size.width - knobSize - horizontalPadding * 2, 0)
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
                                guard !didComplete else { return }
                                dragOffset = min(max(value.translation.width, 0), maxOffset)
                            }
                            .onEnded { _ in
                                guard !didComplete else { return }

                                if dragOffset >= completionThreshold {
                                    didComplete = true

                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                        dragOffset = maxOffset
                                    }

                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        onCompleted()
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("밀어서 루틴 시작하기")
        .accessibilityHint("오른쪽으로 밀면 오늘의 루틴을 시작합니다.")
    }
}
