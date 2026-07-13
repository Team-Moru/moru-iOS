//
//  SkipStepDialogView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import SwiftUI

struct SkipStepDialogView: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            VStack(spacing: 20) {
                Text("이 단계를 건너뛸까요?")
                    .font(AppFont.title2Bold)
                    .foregroundStyle(AppColor.gray600)

                Text("건너뛴 단계는 완료율에 반영되지 않아요.")
                    .font(AppFont.body1NormalSemiBold)
                    .foregroundStyle(AppColor.gray500)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button {
                        onCancel()
                    } label: {
                        Text("취소")
                            .font(AppFont.body1NormalSemiBold)
                            .foregroundStyle(AppColor.gray600)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppColor.grayWhite)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onConfirm()
                    } label: {
                        Text("건너뛰기")
                            .font(AppFont.body1NormalSemiBold)
                            .foregroundStyle(AppColor.grayWhite)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppColor.orange350)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(AppColor.grayWhite)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 32)
        }
    }
}
