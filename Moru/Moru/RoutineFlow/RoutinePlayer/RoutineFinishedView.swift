//
//  RoutineFinishedView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import SwiftUI

struct RoutineFinishedView: View {
    let routineName: String
    let completionRate: Int
    let completedStepCount: Int
    let skippedStepCount: Int
    let onTapTodayRecord: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("루틴 완료")
                .font(AppFont.title2Bold)
                .foregroundStyle(AppColor.grayWhite)

            Text("\(completionRate)%")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.grayWhite)

            VStack(spacing: 8) {
                Text(routineName)
                    .font(AppFont.body1NormalSemiBold)
                    .foregroundStyle(AppColor.grayWhite)

                Text("완료 \(completedStepCount)개 · 건너뜀 \(skippedStepCount)개")
                    .font(AppFont.body1NormalSemiBold)
                    .foregroundStyle(AppColor.grayWhite.opacity(0.8))
            }

            if let onTapTodayRecord {
                Button {
                    onTapTodayRecord()
                } label: {
                    Text("오늘의 기록 확인")
                        .font(AppFont.body1NormalSemiBold)
                        .foregroundStyle(AppColor.babyBlue250)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(AppColor.grayWhite)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }

            Spacer()
        }
    }
}
