//
//  VoiceMicButton.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import SwiftUI

struct VoiceMicButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(AppIcon.moruMicOrb)
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("음성 입력")
    }
}
