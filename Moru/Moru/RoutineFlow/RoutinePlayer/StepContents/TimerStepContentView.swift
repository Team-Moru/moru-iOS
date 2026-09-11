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
import UIKit

private struct RoutinePlayerCaptureTimerRemainingSecondsKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

private struct RoutinePlayerCaptureActiveTimerSegmentIndexKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    var routinePlayerCaptureTimerRemainingSeconds: Int? {
        get { self[RoutinePlayerCaptureTimerRemainingSecondsKey.self] }
        set { self[RoutinePlayerCaptureTimerRemainingSecondsKey.self] = newValue }
    }

    var routinePlayerCaptureActiveTimerSegmentIndex: Int? {
        get { self[RoutinePlayerCaptureActiveTimerSegmentIndexKey.self] }
        set {
            self[RoutinePlayerCaptureActiveTimerSegmentIndexKey.self] = newValue
        }
    }
}

struct RoutineTimerState: Equatable {
    enum Action: Equatable {
        case announce(Int)
        case complete
    }

    private(set) var remainingSeconds: Int
    private(set) var didComplete = false
    private var didStart = false

    init(totalSeconds: Int) {
        remainingSeconds = max(totalSeconds, 1)
    }

    mutating func start() -> [Action] {
        guard !didStart, !didComplete else {
            return []
        }

        didStart = true
        guard (1...5).contains(remainingSeconds) else {
            return []
        }

        return [.announce(remainingSeconds)]
    }

    mutating func tick() -> [Action] {
        guard didStart, !didComplete, remainingSeconds > 0 else {
            return []
        }

        remainingSeconds -= 1
        if remainingSeconds == 0 {
            didComplete = true
            return [.complete]
        }

        guard (1...5).contains(remainingSeconds) else {
            return []
        }

        return [.announce(remainingSeconds)]
    }

    /// 백그라운드에서 잃어버린 초를 한 번에 차감한다. 지나간 카운트다운은 되풀이하지 않고
    /// 현재 남은 초가 1~5초면 그 값만 알린다.
    mutating func catchUp(elapsedSeconds: Int) -> [Action] {
        guard didStart, !didComplete, elapsedSeconds > 0, remainingSeconds > 0 else {
            return []
        }

        remainingSeconds = max(remainingSeconds - elapsedSeconds, 0)
        if remainingSeconds == 0 {
            didComplete = true
            return [.complete]
        }

        guard (1...5).contains(remainingSeconds) else {
            return []
        }

        return [.announce(remainingSeconds)]
    }

    /// 사용자가 남은 시간을 기다리지 않고 단계를 끝낸다. 이후 tick은 아무것도 내지 않는다.
    mutating func completeEarly() -> [Action] {
        guard !didComplete else {
            return []
        }

        didStart = true
        didComplete = true
        return [.complete]
    }

}

struct TimerStepContentView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.routinePlayerCaptureTimerRemainingSeconds)
    private var captureRemainingSeconds
    @Environment(\.routinePlayerCaptureActiveTimerSegmentIndex)
    private var captureActiveTimerSegmentIndex
    let step: RoutineStep
    let isGuidancePlaying: Bool
    /// 안내 음성이 끝날 때까지 기다린다. 확인형·입력형은 이미 이렇게 하고 있었고
    /// 타이머만 곧바로 흘러 안내를 듣는 동안 시간이 깎였다.
    let waitUntilGuidanceFinishes: () async -> Bool
    let onComplete: () -> Void
    let onCountdown: (Int) -> Void
    let onSkip: () -> Void

    @State private var timerState: RoutineTimerState
    /// 백그라운드 진입 시각. 런루프 타이머는 정지된 동안의 tick을 돌려주지 않으므로 복귀 시 벽시계로 보정한다.
    @State private var backgroundEnteredAt: Date?

    private let totalSeconds: Int

    private let timer = Timer
        .publish(every: 1, on: .main, in: .common)
        .autoconnect()

    init(
        step: RoutineStep,
        isGuidancePlaying: Bool,
        waitUntilGuidanceFinishes: @escaping () async -> Bool = { true },
        onComplete: @escaping () -> Void,
        onCountdown: @escaping (Int) -> Void = { _ in },
        onSkip: @escaping () -> Void
    ) {
        let seconds = max(step.estimatedSeconds ?? 60, 1)

        self.step = step
        self.isGuidancePlaying = isGuidancePlaying
        self.waitUntilGuidanceFinishes = waitUntilGuidanceFinishes
        self.onComplete = onComplete
        self.onCountdown = onCountdown
        self.onSkip = onSkip
        self.totalSeconds = seconds

        _timerState = State(
            initialValue: RoutineTimerState(totalSeconds: seconds)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            stepTitleSection

            Spacer()
                .frame(height: timerSegments == nil ? 84 : 74)

            timerProgressView

            Spacer()
                .frame(height: timerSegments == nil ? 52 : 26)

            if let timerSegments {
                timerSegmentList(timerSegments)
            } else {
                guideSection
            }

            Spacer()
                .frame(height: timerSegments == nil ? 48 : 16)

            // 3분 스트레칭을 30초에 끝낸 사용자에게도 완료 경로를 준다.
            MoruButton(
                RoutinePlayerCopy.manualCompletionTitle,
                style: .secondary
            ) {
                handleTimerActions(timerState.completeEarly())
            }
            .padding(.horizontal, 16)
            .accessibilityHint("남은 시간을 기다리지 않고 이 항목을 완료합니다")

            RoutineStepSkipFooterView(
                horizontalPadding: 16,
                onSkip: onSkip
            )
        }
        .padding(.horizontal, 24)
        .onReceive(timer) { _ in
            updateTimer()
        }
        .task {
            // 안내가 끝난 뒤에 시작한다. 중간에 취소되면(단계 이탈·백그라운드)
            // 타이머를 시작하지 않는다.
            guard await waitUntilGuidanceFinishes() else {
                return
            }

            handleTimerActions(timerState.start())
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didEnterBackgroundNotification
            )
        ) { _ in
            backgroundEnteredAt = Date()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willEnterForegroundNotification
            )
        ) { _ in
            guard let backgroundEnteredAt else {
                return
            }

            self.backgroundEnteredAt = nil
            let elapsed = Int(Date().timeIntervalSince(backgroundEnteredAt).rounded(.down))
            handleTimerActions(timerState.catchUp(elapsedSeconds: elapsed))
        }
    }

    // MARK: - Step title

    private var stepTitleSection: some View {
        VStack(spacing: 8) {
            Text(step.title)
                .font(
                    AppFont.pretendardSemiBold(size: 22, relativeTo: .title3)
                )
                .foregroundStyle(AppColor.gray600)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("타이머형 · \(estimatedTimeText)")
                .font(AppFont.pretendardMedium(size: 16, relativeTo: .body))
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
        .frame(
            width: 218,
            height: 218
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("남은 시간 \(timeText)")
    }

    private var timerBackground: some View {
        Circle()
            .fill(AppColor.grayWhite.opacity(0.18))
            .shadow(
                color: AppColor.orange150.opacity(0.34),
                radius: 32,
                x: 0,
                y: 8
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
                value: timerState.remainingSeconds
            )
    }

    private var timerTextSection: some View {
        VStack(spacing: 2) {
            Text("남은 시간")
                .moruTextStyle(
                    timerSegments == nil
                      ? .b4.weight(.semiBold)
                      : .c1.weight(.semiBold)
                )
                .foregroundStyle(AppColor.gray350)

            Text(timeText)
                .font(
                    AppFont.pretendardSemiBold(
                        size: timerSegments == nil ? 48 : 36
                    )
                )
                .foregroundStyle(AppColor.gray550)
                .monospacedDigit()
        }
        // The text lives inside a fixed-size visual gauge. Keep it legible without
        // allowing accessibility scaling to make the two labels overlap; the
        // complete value remains exposed through the gauge's accessibility label.
        .dynamicTypeSize(...DynamicTypeSize.large)
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
                .font(AppFont.pretendardSemiBold(size: 16, relativeTo: .body))
                .foregroundStyle(AppColor.gray500)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }

    private func timerSegmentList(
        _ segments: [RoutinePlayerCopy.TimerSegment]
    ) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(
                            AppFont.pretendardSemiBold(
                                size: 11,
                                relativeTo: .caption2
                            )
                        )
                        .foregroundStyle(
                            index == activeTimerSegmentIndex
                              ? AppColor.grayWhite
                              : AppColor.gray300
                        )
                        .frame(width: 18, height: 18)
                        .background(
                            index == activeTimerSegmentIndex
                              ? AppColor.orange200
                              : AppColor.babyBlue100,
                            in: Circle()
                        )

                    Text(segmentDisplayText(segment))
                        .font(
                            AppFont.pretendardMedium(
                                size: 14,
                                relativeTo: .caption
                            )
                        )
                        .foregroundStyle(
                            index == activeTimerSegmentIndex
                              ? AppColor.gray600
                              : AppColor.gray500
                        )
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                }
                .padding(.horizontal, 18)
                .frame(
                    maxWidth: .infinity,
                    minHeight: dynamicTypeSize.isAccessibilitySize ? 68 : 46
                )
                .background(
                    index == activeTimerSegmentIndex
                      ? AppColor.grayWhite.opacity(0.72)
                      : AppColor.grayWhite.opacity(0.42),
                    in: RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("타이머 세부 항목")
    }

    private var activeTimerSegmentIndex: Int {
        guard let timerSegments else { return 0 }
#if DEBUG
        if let captureActiveTimerSegmentIndex {
            return min(
                max(captureActiveTimerSegmentIndex, 0),
                max(timerSegments.count - 1, 0)
            )
        }
#endif
        let segmentDurations = timerSegments.map { segment -> Int in
            segment.durationSeconds ?? 60
        }
        let elapsedSeconds = max(totalSeconds - displayedRemainingSeconds, 0)
        var cumulativeSeconds = 0

        for (index, duration) in segmentDurations.enumerated() {
            cumulativeSeconds += duration
            if elapsedSeconds < cumulativeSeconds {
                return index
            }
        }

        return max(segmentDurations.count - 1, 0)
    }

    // MARK: - Timer logic

    private func updateTimer() {
        handleTimerActions(timerState.tick())
    }

    private func handleTimerActions(_ actions: [RoutineTimerState.Action]) {
        for action in actions {
            switch action {
            case .announce(let seconds):
                onCountdown(seconds)
            case .complete:
                onComplete()
            }
        }
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
            CGFloat(displayedRemainingSeconds)
            / CGFloat(totalSeconds)

        return min(max(value, 0), 1)
    }

    // MARK: - Text

    private var timeText: String {
        let minutes = displayedRemainingSeconds / 60
        let seconds = displayedRemainingSeconds % 60

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
        RoutinePlayerCopy.guide(for: step)
    }

    private var timerSegments: [RoutinePlayerCopy.TimerSegment]? {
        RoutinePlayerCopy.timerSegments(for: step)
    }

    private var displayedRemainingSeconds: Int {
#if DEBUG
        if let captureRemainingSeconds {
            return min(max(captureRemainingSeconds, 0), totalSeconds)
        }
#endif
        return timerState.remainingSeconds
    }

    private func segmentDisplayText(
        _ segment: RoutinePlayerCopy.TimerSegment
    ) -> String {
        guard let duration = segment.duration else {
            return segment.title
        }

        return "\(segment.title) · \(duration)"
    }
}
