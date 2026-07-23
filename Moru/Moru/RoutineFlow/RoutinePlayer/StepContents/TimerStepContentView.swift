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
    let isGuidancePlaying: Bool
    let onComplete: () -> Void

    @State private var remainingSeconds: Int
    @State private var didComplete = false

    private let totalSeconds: Int

    private let timer = Timer
        .publish(every: 1, on: .main, in: .common)
        .autoconnect()

    init(
        step: RoutineStep,
        isGuidancePlaying: Bool,
        onComplete: @escaping () -> Void
    ) {
        let seconds = max(step.estimatedSeconds ?? 60, 1)

        self.step = step
        self.isGuidancePlaying = isGuidancePlaying
        self.onComplete = onComplete
        self.totalSeconds = seconds

        _remainingSeconds = State(initialValue: seconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            stepTitleSection

            Spacer()
                .frame(height: 68)

            timerProgressView

            Spacer()
                .frame(height: 76)

            guideSection
        }
        .padding(.horizontal, 24)
        .onReceive(timer) { _ in
            updateTimer()
        }
    }

    // MARK: - Step title

    private var stepTitleSection: some View {
        VStack(spacing: 8) {
            Text(step.title)
                .font(AppFont.title3SemiBold)
                .foregroundStyle(AppColor.gray600)
                .multilineTextAlignment(.center)

            Text("타이머형 · \(estimatedTimeText)")
                .font(AppFont.body1NormalMedium)
                .foregroundStyle(AppColor.gray400)
        }
    }

    // MARK: - Timer progress

    private var timerProgressView: some View {
        ZStack {
            timerBackground

            timerProgressCircle

            timerTextSection
        }
        .frame(width: 220, height: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("남은 시간 \(timeText)")
    }

    private var timerBackground: some View {
        Circle()
            .fill(AppColor.grayWhite.opacity(0.38))
            .shadow(
                color: AppColor.orange150.opacity(0.22),
                radius: 30,
                x: 0,
                y: 10
            )
    }

    private var timerProgressCircle: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                AppColor.orange200,
                style: StrokeStyle(
                    lineWidth: 22,
                    lineCap: .butt,
                    lineJoin: .round
                )
            )
            // Circle의 시작 지점을 12시 방향으로 이동
            .rotationEffect(.degrees(-90))
            // 1초 단위 값 변경을 부드럽게 연결
            .animation(
                .linear(duration: 1),
                value: remainingSeconds
            )
    }

    private var timerTextSection: some View {
        VStack(spacing: 2) {
            Text("남은 시간")
                .font(AppFont.body1NormalSemiBold)
                .foregroundStyle(AppColor.gray350)

            Text(timeText)
                .font(AppFont.pretendardSemiBold(size: 48))
                .foregroundStyle(AppColor.gray550)
                .monospacedDigit()
        }
    }

    // MARK: - Guide

    private var guideSection: some View {
        VStack(spacing: 8) {
            if isGuidancePlaying {
                Text("음성 안내 중")
                    .font(AppFont.caption1SemiBold)
                    .foregroundStyle(AppColor.gray350)
            }

            Text(guideText)
                .font(AppFont.body1NormalSemiBold)
                .foregroundStyle(AppColor.gray500)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }

    // MARK: - Timer logic

    private func updateTimer() {
        guard !didComplete else { return }
        guard remainingSeconds > 0 else { return }

        remainingSeconds -= 1

        guard remainingSeconds == 0 else { return }

        didComplete = true
        onComplete()
    }

    /// 전체 설정 시간 중 현재 남아 있는 시간의 비율
    ///
    /// 예:
    /// - 3분 중 3분 남음 → 1.0
    /// - 3분 중 1분 30초 남음 → 0.5
    /// - 3분 중 0초 남음 → 0.0
    private var progress: CGFloat {
        guard totalSeconds > 0 else {
            return 0
        }

        let value =
            CGFloat(remainingSeconds)
            / CGFloat(totalSeconds)

        return min(max(value, 0), 1)
    }

    // MARK: - Text

    private var timeText: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60

        return String(
            format: "%d:%02d",
            minutes,
            seconds
        )
    }

    private var estimatedTimeText: String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes == 0 {
            return "\(seconds)초"
        }

        if seconds == 0 {
            return "\(minutes)분"
        }

        return "\(minutes)분 \(seconds)초"
    }

    private var guideText: String {
        if !step.instruction.isEmpty {
            return step.instruction
        }

        return "눈을 감고 천천히 호흡해봐요."
    }
}
