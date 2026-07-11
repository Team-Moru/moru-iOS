//
//  InputStepContentView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

//
//  InputStepContentView.swift
//  Moru
//

import SwiftUI

struct InputStepContentView: View {
    let step: RoutineStep
    let onComplete: (String) -> Void

    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            stepTitleSection

            Spacer()
                .frame(height: 42)

            RoutinePlayerOrbView()

            Spacer()
                .frame(height: 44)

            VStack(spacing: 8) {
                Text("AI 음성 안내 중")
                    .font(AppFont.caption1SemiBold)
                    .foregroundStyle(AppColor.gray350)

                Text(inputGuideText)
                    .font(AppFont.body1NormalSemiBold)
                    .foregroundStyle(AppColor.gray500)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer()
                .frame(height: 32)

            VoiceMicButton {
                let fallbackText = inputText.isEmpty ? "음성 입력 완료" : inputText
                onComplete(fallbackText)
            }
        }
        .padding(.horizontal, 24)
    }

    private var stepTitleSection: some View {
        VStack(spacing: 8) {
            Text(step.title)
                .font(AppFont.title2Bold)
                .foregroundStyle(AppColor.gray600)
                .multilineTextAlignment(.center)

            Text("입력형 · \(estimatedMinuteText)")
                .font(AppFont.body1NormalMedium)
                .foregroundStyle(AppColor.gray400)
        }
    }

    private var estimatedMinuteText: String {
        let seconds = step.estimatedSeconds ?? 60
        let minutes = max(seconds / 60, 1)
        return "\(minutes)분"
    }

    private var inputGuideText: String {
        if !step.instruction.isEmpty {
            return step.instruction
        }

        return "오늘의 다짐을 크게 말해봐요!\n어떤 하루를 만들고 싶나요?"
    }
}
