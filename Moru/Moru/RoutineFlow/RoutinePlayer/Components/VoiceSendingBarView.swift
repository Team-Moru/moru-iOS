//
//  VoiceSendingBarView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//
import SwiftUI

struct VoiceSendingBarView: View {
    let onPause: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button {
                onPause()
            } label: {
                Image(AppIcon.moruSoundPauseButton)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)

            RoundedRectangle(cornerRadius: 3)
                .fill(AppColor.grayWhite.opacity(0.8))
                .frame(height: 24)
                .overlay {
                    Text("음성 전송 중")
                        .font(AppFont.caption1SemiBold)
                        .foregroundStyle(AppColor.grayWhite.opacity(0.001))
                }

            Button {
                onStop()
            } label: {
                Image(AppIcon.moruSoundStopButton)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 76)
        .background(AppColor.orange200.opacity(0.7))
        .clipShape(Capsule())
        .padding(.horizontal, 20)
    }
}
