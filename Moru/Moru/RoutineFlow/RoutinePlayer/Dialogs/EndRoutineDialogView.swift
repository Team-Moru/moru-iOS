//
//  EndRoutineDialogView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import SwiftUI

struct EndRoutineDialogView: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            MoruDialog(
                title: "루틴을 종료할까요?",
                message: """
                지금까지 완료한 항목만 저장돼요.
                나머지는 미완료로 기록됩니다.
                """,
                primaryTitle: "계속하기",
                secondaryTitle: "종료하기",
                primaryAction: onCancel,
                secondaryAction: onConfirm,
                adaptsForAccessibility: true
            )
            .offset(y: dynamicTypeSize.isAccessibilitySize ? 0 : -12)
        }
        .accessibilityAddTraits(.isModal)
    }
}
