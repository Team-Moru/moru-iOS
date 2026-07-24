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

            MoruDialog(
                title: "이 항목을 건너뛸까요?",
                message: """
                건너뛰면 현재 루틴은 미완료로 기록돼요.
                다음 루틴으로 넘어갈게요.
                """,
                primaryTitle: "계속하기",
                secondaryTitle: "건너뛰기",
                primaryAction: onCancel,
                secondaryAction: onConfirm,
                adaptsForAccessibility: true
            )
            .offset(y: -12)
        }
        .accessibilityAddTraits(.isModal)
    }
}
