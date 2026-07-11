//
//  AlarmRoutineCardView.swift
//  Moru
//
//  Created by 김승겸 on 7/7/26.
//

import SwiftUI

struct AlarmRoutineCardView: View {
    let title: String
    let routineName: String
    let minutes: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(AppFont.label1NormalSemiBold)
                .foregroundStyle(AppColor.gray350)

            Text("\(routineName) · \(minutes)분")
                .font(AppFont.body1NormalSemiBold)
                .foregroundStyle(AppColor.gray450)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .alarmGlass(
            in: RoundedRectangle(cornerRadius: 24, style: .continuous),
            tint: AppColor.grayWhite,
            opacity: 0.18,
            strokeOpacity: 0.8
        )
    }
}
