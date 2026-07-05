//
//  MoruVoiceSegmentedControl.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

enum MoruVoiceSegment: CaseIterable {
  case basic
  case full

  var title: String {
    switch self {
    case .basic:
      "기본 음성"
    case .full:
      "전체 음성"
    }
  }
}

struct MoruVoiceSegmentedControl: View {
  @Binding var selection: MoruVoiceSegment

  var body: some View {
    HStack(spacing: AppSpacing.sm) {
      ForEach(MoruVoiceSegment.allCases, id: \.self) { segment in
        Button {
          selection = segment
        } label: {
          Text(segment.title)
            .font(AppFont.pretendardSemiBold(size: 16))
            .foregroundStyle(
              selection == segment ? AppColor.moruTextPrimary : AppColor.moruTextSecondary
            )
            .frame(width: 164, height: 42)
            .background(selection == segment ? AppColor.grayWhite : AppColor.moruBlueDisabled)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
        }
        .buttonStyle(.plain)
      }
    }
  }
}
