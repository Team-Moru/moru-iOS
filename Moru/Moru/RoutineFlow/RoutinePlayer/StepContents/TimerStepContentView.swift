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

struct TimerStepContentView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.routinePlayerCaptureTimerRemainingSeconds)
    private var captureRemainingSeconds
    @Environment(\.routinePlayerCaptureActiveTimerSegmentIndex)
    private var captureActiveTimerSegmentIndex
    let step: RoutineStep
    let isGuidancePlaying: Bool
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var remainingSeconds: Int
    @State private var didComplete = false

    private let totalSeconds: Int

    private let timer = Timer
        .publish(every: 1, on: .main, in: .common)
        .autoconnect()

    init(
        step: RoutineStep,
        isGuidancePlaying: Bool,
        onComplete: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        let seconds = max(step.estimatedSeconds ?? 60, 1)

        self.step = step
        self.isGuidancePlaying = isGuidancePlaying
        self.onComplete = onComplete
        self.onSkip = onSkip
        self.totalSeconds = seconds

        _remainingSeconds = State(initialValue: seconds)
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
                .frame(height: timerSegments == nil ? 116 : 16)

            HStack(spacing: 0) {
                Button {
                    completeTimer()
                } label: {
                    Text("완료했어요")
                        .font(
                            AppFont.pretendardMedium(
                                size: 14,
                                relativeTo: .caption
                            )
                        )
                        .foregroundStyle(AppColor.gray400)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("타이머를 끝내고 이 단계를 완료합니다")

                Button(action: onSkip) {
                    Text("건너뛰기")
                        .font(
                            AppFont.pretendardMedium(
                                size: 14,
                                relativeTo: .caption
                            )
                        )
                        .foregroundStyle(AppColor.gray300)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
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
                value: remainingSeconds
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
        .accessibilityLabel("스트레칭 순서")
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
        guard !didComplete else { return }
        guard remainingSeconds > 0 else { return }

        remainingSeconds -= 1

        guard remainingSeconds == 0 else { return }

        completeTimer()
    }

    private func completeTimer() {
        guard !didComplete else { return }

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
        return remainingSeconds
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
