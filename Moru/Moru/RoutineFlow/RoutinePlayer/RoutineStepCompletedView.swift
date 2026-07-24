//
//  RoutineStepCompletedView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import SwiftUI

struct RoutineStepCompletedView: View {
    let stepTitle: String
    let isGuidancePlaying: Bool
    let onFinish: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(AppImage.moruRoutineCompleted)
                .resizable()
                .scaledToFit()
                .frame(width: 190, height: 190)
                .scaleEffect(1.28)

            Spacer()
                .frame(height: 54)

            VStack(spacing: 12) {
                Text("\(stepTitle)가\n완료되었어요")
                    .font(AppFont.pretendardBold(size: 28, relativeTo: .title2))
                    .foregroundStyle(AppColor.gray600)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("다음 항목으로 넘어갈게요")
                    .font(AppFont.pretendardMedium(size: 16, relativeTo: .body))
                    .foregroundStyle(AppColor.gray350)

                if isGuidancePlaying {
                    Text("음성 안내 중")
                        .font(AppFont.caption1SemiBold)
                        .foregroundStyle(AppColor.gray350)
                }
            }

            Spacer()
        }
        
        .task {
            do {
                try await Task.sleep(
                    nanoseconds: 1_000_000_000
                )

                guard !Task.isCancelled else { return }

                await onFinish()
            } catch {
                // 화면이 사라져 Task가 취소된 경우에는
                // 다음 단계로 이동하지 않습니다.
            }
        }
    }
}

#Preview {
    RoutineStepCompletedView(
        stepTitle: "잠자리 정리하기",
        isGuidancePlaying: true,
        onFinish: {
            print("다음 루틴 단계로 이동")
        }
    )
    .background(AppColor.babyBlue50.ignoresSafeArea())
}
