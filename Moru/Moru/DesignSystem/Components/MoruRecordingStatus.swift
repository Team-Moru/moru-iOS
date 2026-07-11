//
//  MoruRecordingStatus.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruRecordingStatus: View {
  let isRecording: Bool

  var body: some View {
    HStack(spacing: AppSpacing.xs) {
      Circle()
        .fill(isRecording ? AppColor.coral300 : AppColor.gray300)
        .frame(width: 8, height: 8)

      Text(isRecording ? "녹음 중" : "녹음 종료")
        .font(AppFont.caption1SemiBold)
        .foregroundStyle(isRecording ? AppColor.coral300 : AppColor.gray400)
    }
    .padding(.horizontal, AppSpacing.sm)
    .frame(height: 30)
    .background(isRecording ? AppColor.coral100 : AppColor.gray150)
    .clipShape(Capsule())
  }
}
