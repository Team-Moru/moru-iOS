//
//  TimerStepContentView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

//
//  TimerStepContentView.swift
//  Moru
//

import SwiftUI
import Combine

struct TimerStepContentView: View {
    let step: RoutineStep
    let onComplete: () -> Void

    @State private var remainingSeconds: Int
    @State private var isRunning = true

    init(
        step: RoutineStep,
        onComplete: @escaping () -> Void
    ) {
        self.step = step
        self.onComplete = onComplete
        _remainingSeconds = State(initialValue: step.estimatedSeconds ?? 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            stepTitleSection

            Spacer()
                .frame(height: 42)

            RoutinePlayerOrbView()

            Spacer()
                .frame(height: 40)

            VStack(spacing: 8) {
                Text(isRunning ? "타이머 진행 중" : "타이머 일시정지")
                    .font(AppFont.caption1SemiBold)
                    .foregroundStyle(AppColor.gray350)

                Text(timeText)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.gray500)
            }

            Spacer()
                .frame(height: 32)

            HStack(spacing: 12) {
                Button {
                    isRunning.toggle()
                } label: {
                    Text(isRunning ? "일시정지" : "다시 시작")
                        .font(AppFont.body1NormalSemiBold)
                        .foregroundStyle(AppColor.grayWhite)
                        .frame(width: 120, height: 52)
                        .background(AppColor.orange250)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onComplete()
                } label: {
                    Text("완료")
                        .font(AppFont.body1NormalSemiBold)
                        .foregroundStyle(AppColor.grayWhite)
                        .frame(width: 100, height: 52)
                        .background(AppColor.orange350)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard isRunning else { return }
            guard remainingSeconds > 0 else { return }

            remainingSeconds -= 1

            if remainingSeconds == 0 {
                onComplete()
            }
        }
    }

    private var stepTitleSection: some View {
        VStack(spacing: 8) {
            Text(step.title)
                .font(AppFont.title2Bold)
                .foregroundStyle(AppColor.gray600)
                .multilineTextAlignment(.center)

            Text("타이머형 · \(estimatedMinuteText)")
                .font(AppFont.body1NormalMedium)
                .foregroundStyle(AppColor.gray400)
        }
    }

    private var estimatedMinuteText: String {
        let totalSeconds = step.estimatedSeconds ?? 60

        if totalSeconds < 60 {
            return "1분"
        }

        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if seconds == 0 {
            return "\(minutes)분"
        }

        return "\(minutes)분 \(seconds)초"
    }

    private var timeText: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
