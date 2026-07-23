//
//  HistoryComponents.swift
//  Moru
//
//  Created by Codex on 7/14/26.
//

import Foundation
import SwiftUI

struct HistorySectionHeader: View {
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(AppFont.caption1Bold)
                .foregroundStyle(AppColor.gray500)

            Spacer()

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: AppSpacing.xxs) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                    }
                    .font(AppFont.caption1Medium)
                    .foregroundStyle(AppColor.gray500)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct HistoryWeeklySummaryCard: View {
    let title: String
    let completedRuns: Int
    let totalRuns: Int
    let completionRate: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("이번 주 리포트")
                        .font(AppFont.caption1Medium)
                        .foregroundStyle(AppColor.gray400)

                    Text("\(Int((completionRate * 100).rounded()))%")
                        .font(AppFont.pretendardBold(size: 30))
                        .foregroundStyle(AppColor.grayWhite)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                    Text(title)
                        .font(AppFont.caption1Medium)
                        .foregroundStyle(AppColor.gray500)

                    Text("\(completedRuns)/\(max(totalRuns, 1))회 완료")
                        .font(AppFont.caption1SemiBold)
                        .foregroundStyle(AppColor.grayWhite)
                }
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(AppColor.grayBlack)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(title), 이번 주 리포트, \(completedRuns)/\(totalRuns)회 완료, "
            + "완수율 \(Int((completionRate * 100).rounded()))퍼센트"
        )
    }
}

struct HistoryWakeMetricsView: View {
    let metrics: HistoryWakeMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HistorySectionHeader(title: "기상 시간 패턴", actionTitle: nil, action: nil)

            VStack(spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.md) {
                    HistoryMetricBlock(
                        title: "평균 기상 시각",
                        value: averageWakeText,
                        detail: averageDetailText
                    )

                    Rectangle()
                        .fill(AppColor.moruBorder)
                        .frame(width: 1, height: 66)

                    HistoryMetricBlock(
                        title: "기상 규칙성",
                        value: regularityScoreText,
                        detail: deviationText
                    )
                }
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.grayWhite)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.xs)
                    .stroke(AppColor.moruBorder, lineWidth: 1)
            }
        }
    }

    private var averageWakeText: String {
        guard case .calculated(_, let minute, _, _) = metrics else {
            return metrics == .unavailable ? "--:--" : "계산 중"
        }

        return String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private var averageDetailText: String {
        switch metrics {
        case .calculated:
            return "지난 기록 기준"
        case .insufficient(let count):
            return "기록 \(count)회 · 3회부터 계산"
        case .unavailable:
            return "기록 없음"
        }
    }

    private var regularityScoreText: String {
        guard case .calculated(_, _, _, let regularity) = metrics else {
            return "--점"
        }

        return "\(regularity.score)점"
    }

    private var deviationText: String {
        guard case .calculated(_, _, let minutes, let regularity) = metrics else {
            return "편차 기록 없음"
        }

        return "편차 ±\(minutes)분 · \(regularity.shortText)"
    }
}

private struct HistoryMetricBlock: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(title)
                .font(AppFont.caption1Medium)
                .foregroundStyle(AppColor.gray500)

            Text(value)
                .font(AppFont.pretendardBold(size: 28))
                .foregroundStyle(AppColor.grayBlack)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(detail)
                .font(AppFont.pretendardRegular(size: 11))
                .foregroundStyle(AppColor.gray500)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HistoryWeeklyCompletionChart: View {
    let completions: [HistoryDailyCompletion]
    let calendar: Calendar
    var onSelect: ((HistoryDailyCompletion) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HistorySectionHeader(title: "이번 주 완수율", actionTitle: nil, action: nil)

            VStack(spacing: AppSpacing.sm) {
                HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                    ForEach(completions, id: \.date) { completion in
                        HistoryWeekBar(
                            completion: completion,
                            calendar: calendar,
                            action: onSelect.map { select in
                                { select(completion) }
                            }
                        )
                    }
                }
                .frame(height: 92)

                Text(weeklyInsight)
                    .font(AppFont.pretendardRegular(size: 10))
                    .foregroundStyle(AppColor.gray500)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(AppColor.gray100)
                    .clipShape(Capsule())
            }
            .padding(AppSpacing.md)
            .background(AppColor.grayWhite)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.xs)
                    .stroke(AppColor.moruBorder, lineWidth: 1)
            }
        }
    }

    private var weeklyInsight: String {
        guard let minCompletion = completions.min(
            by: { $0.completionRate < $1.completionRate }
        ), let maxCompletion = completions.max(
            by: { $0.completionRate < $1.completionRate }
        ) else {
            return "이번 주 기록을 쌓고 있어요"
        }

        let minDay = historyWeekdayText(minCompletion.date, calendar: calendar)
        let maxDay = historyWeekdayText(maxCompletion.date, calendar: calendar)
        return "\(minDay)요일 완수율이 가장 낮아요 (\(rateText(minCompletion)))"
            + " · \(maxDay)요일이 가장 꾸준해요"
    }

    private func rateText(_ completion: HistoryDailyCompletion) -> String {
        "\(Int((completion.completionRate * 100).rounded()))%"
    }
}

struct HistoryStepAnalysisItem: Identifiable, Equatable {
    let title: String
    let completedCount: Int
    let totalCount: Int

    var id: String {
        title
    }

    var completionRate: Double {
        guard totalCount > 0 else {
            return 0
        }

        return Double(completedCount) / Double(totalCount)
    }

    var completionText: String {
        "완료 \(completedCount)회 / 미완료 \(max(totalCount - completedCount, 0))회"
    }
}

struct HistoryWeeklyStepAnalysisView: View {
    let items: [HistoryStepAnalysisItem]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HistorySectionHeader(title: "항목별 분석", actionTitle: nil, action: nil)

            VStack(spacing: AppSpacing.sm) {
                if items.isEmpty {
                    Text("이번 주 항목별 기록이 없어요")
                        .font(AppFont.caption1Medium)
                        .foregroundStyle(AppColor.gray500)
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    ForEach(items) { item in
                        HistoryStepAnalysisRow(item: item)
                    }
                }
            }
        }
    }
}

private struct HistoryStepAnalysisRow: View {
    let item: HistoryStepAnalysisItem

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(AppFont.label1NormalMedium)
                    .foregroundStyle(AppColor.grayBlack)
                    .lineLimit(1)

                Spacer()

                Text(item.completionText)
                    .font(AppFont.pretendardRegular(size: 10))
                    .foregroundStyle(AppColor.gray500)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HistoryCompletionRateBar(completionRate: item.completionRate)
        }
        .padding(AppSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(AppColor.grayWhite)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.xs)
                .stroke(AppColor.moruBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.title), 완료율 "
            + "\(Int((item.completionRate * 100).rounded()))퍼센트, "
            + item.completionText
        )
    }
}

private struct HistoryWeekBar: View {
    let completion: HistoryDailyCompletion
    let calendar: Calendar
    let action: (() -> Void)?

    var body: some View {
        Button(action: {
            guard completion.completionRate > 0 else {
                return
            }

            action?()
        }) {
            VStack(spacing: AppSpacing.xxs) {
                Spacer(minLength: 0)

                RoundedRectangle(cornerRadius: 3)
                    .fill(completion.completionRate > 0 ? AppColor.grayBlack : AppColor.gray150)
                    .frame(height: max(4, 58 * completion.completionRate))

                Text(historyWeekdayText(completion.date, calendar: calendar))
                    .font(AppFont.pretendardRegular(size: 10))
                    .foregroundStyle(AppColor.gray500)

                Text(
                    completion.completionRate > 0
                        ? "\(Int((completion.completionRate * 100).rounded()))%"
                        : "-"
                )
                    .font(AppFont.pretendardRegular(size: 9))
                    .foregroundStyle(AppColor.gray500)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(completion.completionRate <= 0 || action == nil)
        .accessibilityLabel(
            "\(historyWeekdayText(completion.date, calendar: calendar))요일 완료율 "
            + "\(Int((completion.completionRate * 100).rounded()))퍼센트"
        )
        .accessibilityHint(
            completion.completionRate > 0
                ? "날짜별 상세 화면으로 이동합니다"
                : "기록이 없습니다"
        )
    }
}

struct HistoryHeatmapCellPresentation: Equatable {
    let accessibilityLabel: String?
    let isAccessibilityHidden: Bool

    init(day: HistoryHeatmapDay, calendar: Calendar) {
        guard let date = day.date else {
            accessibilityLabel = nil
            isAccessibilityHidden = true
            return
        }

        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let dateText: String

        if let year = components.year, let month = components.month, let day = components.day {
            dateText = "\(year)년 \(month)월 \(day)일"
        } else {
            dateText = "날짜"
        }

        if let completionRate = day.completionRate {
            accessibilityLabel = "\(dateText), 완료율 "
            + "\(Int((completionRate * 100).rounded()))퍼센트"
        } else {
            accessibilityLabel = "\(dateText), 기록 없음"
        }
        isAccessibilityHidden = false
    }
}

struct HistoryMonthlyHeatmapView: View {
    let heatmap: HistoryMonthlyHeatmap
    let calendar: Calendar

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: AppSpacing.xxs),
        count: 7
    )

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HistorySectionHeader(title: "월간 히트맵", actionTitle: monthText, action: nil)

            VStack(spacing: AppSpacing.sm) {
                LazyVGrid(columns: columns, spacing: AppSpacing.xxs) {
                    ForEach(
                        ["일", "월", "화", "수", "목", "금", "토"],
                        id: \.self
                    ) { weekday in
                        Text(weekday)
                            .font(AppFont.pretendardRegular(size: 10))
                            .foregroundStyle(AppColor.gray500)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("\(weekday)요일")
                            .accessibilityAddTraits(.isHeader)
                    }

                    ForEach(heatmap.days) { day in
                        let presentation = HistoryHeatmapCellPresentation(
                            day: day,
                            calendar: calendar
                        )

                        ZStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(fillColor(for: day.bucket))

                            if let date = day.date {
                                Text("\(calendar.component(.day, from: date))")
                                    .font(AppFont.pretendardRegular(size: 9))
                                    .foregroundStyle(
                                        day.bucket == .noData
                                            ? AppColor.gray500
                                            : AppColor.grayWhite
                                    )
                            }
                        }
                        .frame(height: 24)
                        .accessibilityLabel(presentation.accessibilityLabel ?? "")
                        .accessibilityHidden(presentation.isAccessibilityHidden)
                    }
                }

                HStack(spacing: AppSpacing.sm) {
                    legendItem("기록 없음", bucket: .noData)
                    legendItem("일부", bucket: .high)
                    legendItem("완료", bucket: .complete)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AppSpacing.md)
            .background(AppColor.grayWhite)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.xs)
                    .stroke(AppColor.moruBorder, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.heatmap")
    }

    private var monthText: String {
        let month = calendar.component(.month, from: heatmap.monthStartDate)
        return "\(month)월"
    }

    private func legendItem(
        _ label: String,
        bucket: HistoryHeatmapBucket
    ) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            RoundedRectangle(cornerRadius: 3)
                .fill(fillColor(for: bucket))
                .frame(width: 10, height: 10)

            Text(label)
                .font(AppFont.pretendardRegular(size: 10))
                .foregroundStyle(AppColor.gray500)
        }
        .accessibilityElement(children: .combine)
    }

    private func fillColor(for bucket: HistoryHeatmapBucket) -> Color {
        switch bucket {
        case .noData:
            return AppColor.gray100
        case .zero:
            return AppColor.gray200
        case .low:
            return AppColor.gray350
        case .high:
            return AppColor.gray550
        case .complete:
            return AppColor.grayBlack
        }
    }
}

struct HistoryCompletionRateBar: View {
    let completionRate: Double
    var fillColor: Color = AppColor.grayBlack

    private var clampedCompletionRate: Double {
        min(max(completionRate, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColor.gray150)

                Capsule()
                    .fill(fillColor)
                    .frame(width: proxy.size.width * clampedCompletionRate)
            }
        }
        .frame(height: AppSpacing.six)
        .accessibilityValue("\(Int((clampedCompletionRate * 100).rounded()))%")
    }
}

struct HistoryRunRow: View {
    let routineName: String
    let timeText: String
    let completionText: String
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "xmark.circle")
                .font(AppFont.body1NormalSemiBold)
                .foregroundStyle(isCompleted ? AppColor.grayBlack : AppColor.gray350)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(routineName)
                    .font(AppFont.label1NormalMedium)
                    .foregroundStyle(isCompleted ? AppColor.grayBlack : AppColor.gray500)
                    .lineLimit(1)

                Text(timeText)
                    .font(AppFont.pretendardRegular(size: 11))
                    .foregroundStyle(AppColor.gray500)
            }

            Spacer()

            Text(completionText)
                .font(AppFont.pretendardRegular(size: 11))
                .foregroundStyle(isCompleted ? AppColor.grayBlack : AppColor.gray350)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxs)
                .background(AppColor.gray100)
                .clipShape(Capsule())
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(AppColor.grayWhite)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.xs)
                .stroke(AppColor.moruBorder, lineWidth: 1)
        }
    }
}

struct HistoryStepResultRow: View {
    let index: Int
    let title: String
    let resultText: String
    let isCompleted: Bool
    let transcript: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(isCompleted ? AppColor.grayBlack : AppColor.gray100)
                        .frame(width: 22, height: 22)

                    Image(systemName: isCompleted ? "checkmark" : "minus")
                        .font(AppFont.pretendardBold(size: 10))
                        .foregroundStyle(isCompleted ? AppColor.grayWhite : AppColor.gray400)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(title)
                        .font(AppFont.label1NormalMedium)
                        .foregroundStyle(isCompleted ? AppColor.grayBlack : AppColor.gray500)
                        .lineLimit(1)

                    Text(resultText)
                        .font(AppFont.pretendardRegular(size: 11))
                        .foregroundStyle(AppColor.gray500)
                }

                Spacer()

                Text(resultText)
                    .font(AppFont.pretendardRegular(size: 11))
                    .foregroundStyle(isCompleted ? AppColor.grayBlack : AppColor.gray350)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(AppColor.gray100)
                    .clipShape(Capsule())
            }

            if let transcript, !transcript.isEmpty {
                Text(transcript)
                    .font(AppFont.caption1Medium)
                    .foregroundStyle(AppColor.moruTextBody)
                    .padding(AppSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColor.gray100)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                    .accessibilityLabel("음성 기록: \(transcript)")
            }
        }
        .padding(AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.grayWhite)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.xs)
                .stroke(AppColor.moruBorder, lineWidth: 1)
        }
    }
}

struct HistoryLoadingView: View {
    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            ProgressView()
                .tint(AppColor.grayBlack)
            Text("기록을 불러오는 중이에요.")
                .font(AppFont.label1NormalMedium)
                .foregroundStyle(AppColor.moruTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct HistoryEmptyView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "calendar.badge.clock")
                .font(AppFont.title1SemiBold)
                .foregroundStyle(AppColor.grayBlack)

            Text(title)
                .font(AppFont.heading3SemiBold)
                .foregroundStyle(AppColor.moruTextPrimary)

            Text(message)
                .font(AppFont.label1NormalMedium)
                .foregroundStyle(AppColor.moruTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppSpacing.xxl)
    }
}

struct HistoryFailureView: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppFont.title1SemiBold)
                .foregroundStyle(AppColor.grayBlack)

            Text(message)
                .font(AppFont.heading3SemiBold)
                .foregroundStyle(AppColor.moruTextPrimary)

            Text("잠시 후 다시 시도해 주세요.")
                .font(AppFont.label1NormalMedium)
                .foregroundStyle(AppColor.moruTextSecondary)
                .multilineTextAlignment(.center)

            MoruButton("다시 시도", style: .secondary, action: retryAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppSpacing.xxl)
    }
}

func historyWeekdayText(_ date: Date, calendar: Calendar) -> String {
    let symbols = ["일", "월", "화", "수", "목", "금", "토"]
    let weekday = calendar.component(.weekday, from: date)
    return symbols[max(0, min(weekday - 1, symbols.count - 1))]
}
