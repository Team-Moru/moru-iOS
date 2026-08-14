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
    let completionRateChangePercentagePoints: Int?
    let averageDurationText: String
    let durationTitle: String
    let runCountsAvailable: Bool

    init(
        title: String,
        completedRuns: Int,
        totalRuns: Int,
        completionRate: Double,
        completionRateChangePercentagePoints: Int?,
        averageDurationText: String,
        durationTitle: String = HistoryCopy.averageDuration,
        runCountsAvailable: Bool = true
    ) {
        self.title = title
        self.completedRuns = completedRuns
        self.totalRuns = totalRuns
        self.completionRate = completionRate
        self.completionRateChangePercentagePoints =
            completionRateChangePercentagePoints
        self.averageDurationText = averageDurationText
        self.durationTitle = durationTitle
        self.runCountsAvailable = runCountsAvailable
    }

    var body: some View {
        HistoryReportSummaryCard(
            compactTextOrder: .weeklyCompact,
            metrics: [
                HistoryReportMetric(
                    title: HistoryCopy.weeklyCompletionRate,
                    value: "\(Int((completionRate * 100).rounded()))%"
                ),
                HistoryReportMetric(
                    title: HistoryCopy.comparedToLastWeek,
                    value: comparisonText
                ),
                HistoryReportMetric(
                    title: durationTitle,
                    value: averageDurationText
                ),
            ]
        )
        .accessibilityLabel(
            "\(title), " + runCountAccessibilityText + ", "
              + "완수율 \(Int((completionRate * 100).rounded()))퍼센트, "
              + comparisonAccessibilityText
              + ", \(durationTitle) \(averageDurationText)"
        )
    }

    private var runCountAccessibilityText: String {
        guard runCountsAvailable else {
            return "계정 집계에는 실행 횟수 정보 없음"
        }

        return "\(completedRuns)/\(totalRuns)회 완료"
    }

    private var comparisonText: String {
        guard let change = completionRateChangePercentagePoints else {
            return "—"
        }

        let prefix = change > 0 ? "+" : ""
        return "\(prefix)\(change)%p"
    }

    private var comparisonAccessibilityText: String {
        guard let change = completionRateChangePercentagePoints else {
            return "지난주 비교 데이터 없음"
        }

        return "지난주 대비 \(change)퍼센트포인트"
    }
}

struct HistoryReportMetric: Identifiable, Equatable {
    let title: String
    let value: String
    var systemImage: String?

    var id: String {
        title
    }
}

enum HistoryReportMetricTextOrder: Equatable {
    case titleThenValue
    case valueThenTitle

    static let weeklyCompact: Self = .titleThenValue

    func resolved(for dynamicTypeSize: DynamicTypeSize) -> Self {
        dynamicTypeSize.isAccessibilitySize ? .valueThenTitle : self
    }
}

struct HistoryReportSummaryCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var compactTextOrder: HistoryReportMetricTextOrder = .valueThenTitle
    let metrics: [HistoryReportMetric]

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: MoruPilotSpacing.twenty) {
                    ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                        metricView(metric)

                        if index < metrics.count - 1 {
                            Divider()
                                .overlay(AppColor.orange100.opacity(0.8))
                        }
                    }
                }
                .padding(MoruPilotSpacing.twenty)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                        metricView(metric)

                        if index < metrics.count - 1 {
                            Rectangle()
                                .fill(AppColor.orange100.opacity(0.8))
                                .frame(width: 1, height: 74)
                        }
                    }
                }
                .padding(.horizontal, MoruPilotSpacing.twenty)
                .frame(minHeight: 110)
            }
        }
        .frame(maxWidth: .infinity)
        .background(MoruPilotColor.summarySurface)
        .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard))
        .shadow(color: MoruPilotColor.shadow, radius: 15, x: 0, y: 0)
    }

    private func metricView(_ metric: HistoryReportMetric) -> some View {
        VStack(spacing: 0) {
            if let systemImage = metric.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(MoruPilotColor.accentSurface)
                    .accessibilityHidden(true)
            }

            if compactTextOrder.resolved(for: dynamicTypeSize) == .titleThenValue {
                metricTitle(metric)
                metricValue(metric)
            } else {
                metricValue(metric)
                metricTitle(metric)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func metricTitle(_ metric: HistoryReportMetric) -> some View {
        Text(metric.title)
            .historyOverviewTextStyle(.c1)
            .foregroundStyle(MoruPilotColor.textPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func metricValue(_ metric: HistoryReportMetric) -> some View {
        Text(metric.value)
            .historyOverviewTextStyle(.h1.weight(.bold))
            .foregroundStyle(MoruPilotColor.textStrong)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(0.62)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct HistoryWakeMetricsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let metrics: HistoryWakeMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HistoryPilotSectionHeader(title: "기상 시간 패턴")

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: MoruPilotSpacing.twenty) {
                        averageWakeMetric

                        Divider()
                            .overlay(MoruPilotColor.border)

                        regularityMetric
                    }
                    .padding(MoruPilotSpacing.twenty)
                } else {
                    HStack(spacing: MoruPilotSpacing.sixteen) {
                        averageWakeMetric

                        Rectangle()
                            .fill(MoruPilotColor.border)
                            .frame(width: 1, height: 74)

                        regularityMetric
                    }
                    .padding(.horizontal, MoruPilotSpacing.twenty)
                    .frame(height: 111)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(historyPilotSurface)
            .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard))
            .shadow(
                color: MoruPilotColor.shadow,
                radius: 15,
                x: 0,
                y: 0
            )
            .padding(.vertical, MoruPilotSpacing.eight)
        }
    }

    private var averageWakeMetric: some View {
        HistoryMetricBlock(
            title: "평균 기상 시각",
            value: averageWakeText,
            detail: averageDetailText
        )
    }

    private var regularityMetric: some View {
        HistoryMetricBlock(
            title: "기상 규칙성",
            value: regularityScoreText,
            detail: deviationText
        )
    }

    private var averageWakeText: String {
        switch metrics {
        case .calculated(_, let minute, _, _, _):
            return String(format: "%02d:%02d", minute / 60, minute % 60)
        case .account(let account):
            guard let minute = account.averageWakeMinute else {
                return "--:--"
            }
            return String(format: "%02d:%02d", minute / 60, minute % 60)
        case .insufficient:
            return "계산 중"
        case .unavailable:
            return "--:--"
        }
    }

    private var averageDetailText: String {
        switch metrics {
        case .calculated:
            return "최근 7일 기준"
        case .account(let account):
            guard let difference = account.wakeTimeDifferenceMinutes else {
                return "계정 기록 기준"
            }
            if difference == 0 {
                return "지난주와 같은 시각"
            }
            return "지난주보다 \(abs(difference))분 "
              + (difference < 0 ? "일찍" : "늦게")
        case .insufficient(let count):
            return "기록 \(count)회 · 3회부터 계산"
        case .unavailable:
            return "기록 없음"
        }
    }

    private var regularityScoreText: String {
        switch metrics {
        case .calculated(_, _, _, let score, _):
            return "\(score)점"
        case .account(let account):
            guard let score = account.resolvedRegularityScore else {
                return "--점"
            }
            return "\(score)점"
        case .insufficient, .unavailable:
            return "--점"
        }
    }

    private var deviationText: String {
        switch metrics {
        case .calculated(_, _, let minutes, _, let regularity):
            return "표준편차 \(minutes)분 · \(regularity.shortText)"
        case .account(let account):
            if let minutes = account.standardDeviationMinutes {
                return "표준편차 \(minutes)분 · \(account.resolvedRegularityLabel)"
            }
            return account.resolvedRegularityLabel
        case .insufficient, .unavailable:
            return "편차 기록 없음"
        }
    }
}

private struct HistoryMetricBlock: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .historyOverviewTextStyle(.c2)
                .foregroundStyle(MoruPilotColor.textTertiary)

            Text(value)
                .historyOverviewTextStyle(.h1.weight(.bold))
                .foregroundStyle(MoruPilotColor.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(detail)
                .historyOverviewTextStyle(.c2)
                .foregroundStyle(MoruPilotColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryPilotSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .historyOverviewTextStyle(.b4.weight(.semiBold))
            .foregroundStyle(AppColor.gray400)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
    }
}

var historyPilotSurface: Color {
    AppColor.grayWhite.opacity(0.2)
}

struct HistoryWeeklyCompletionChart: View {
    let completions: [HistoryDailyCompletion]
    let calendar: Calendar
    var onSelect: ((HistoryDailyCompletion) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HistoryPilotSectionHeader(title: HistoryCopy.weekdayCompletionRate)

            VStack(spacing: MoruPilotSpacing.twelve) {
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
                .frame(height: 112)
            }
            .padding(.horizontal, MoruPilotSpacing.twenty)
            .padding(.vertical, MoruPilotSpacing.twenty)
            .background(historyPilotSurface)
            .clipShape(RoundedRectangle(cornerRadius: MoruPilotSpacing.twelve))
            .shadow(color: MoruPilotColor.shadow, radius: 15, x: 0, y: 0)
            .padding(.vertical, MoruPilotSpacing.eight)
        }
    }
}

struct HistoryStepAnalysisItem: Identifiable, Equatable {
    let id: String
    let title: String
    let completionRate: Double
    let completionText: String

    init(
        title: String,
        completedCount: Int,
        totalCount: Int
    ) {
        id = "device-\(title)"
        self.title = title
        completionRate = totalCount > 0
          ? Double(completedCount) / Double(totalCount)
          : 0
        completionText =
          "완료 \(completedCount)회 / 미완료 "
          + "\(max(totalCount - completedCount, 0))회"
    }

    init(
        accountRoutineID: Int64,
        title: String,
        completionRate: Double
    ) {
        id = "account-\(accountRoutineID)"
        self.title = title
        self.completionRate = completionRate
        completionText = "계정 집계 기준"
    }
}

struct HistoryWeeklyStepAnalysisView: View {
    let items: [HistoryStepAnalysisItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HistoryPilotSectionHeader(title: HistoryCopy.itemAnalysis)

            VStack(spacing: MoruPilotSpacing.eight) {
                if items.isEmpty {
                    HistoryInlineEmptyCard(
                        message: "이번 주 항목별 기록이 없어요."
                    )
                } else {
                    ForEach(items) { item in
                        HistoryStepAnalysisRow(item: item)
                    }
                }
            }
            .padding(.vertical, MoruPilotSpacing.eight)
        }
    }
}

private struct HistoryStepAnalysisRow: View {
    let item: HistoryStepAnalysisItem

    var body: some View {
        VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .historyOverviewTextStyle(.b4.weight(.semiBold))
                    .foregroundStyle(MoruPilotColor.textStrong)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Text("완수율 \(Int((item.completionRate * 100).rounded()))%")
                    .historyOverviewTextStyle(.c1)
                    .foregroundStyle(MoruPilotColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HistoryCompletionRateBar(
                completionRate: item.completionRate,
                fillColor: MoruPilotColor.accent
            )
        }
        .padding(MoruPilotSpacing.sixteen)
        .frame(maxWidth: .infinity, minHeight: 75, alignment: .leading)
        .background(AppColor.grayWhite)
        .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.title), 완수율 "
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
            guard completion.hasData else {
                return
            }

            action?()
        }) {
            VStack(spacing: AppSpacing.xxs) {
                Spacer(minLength: 0)

                RoundedRectangle(cornerRadius: MoruPilotSpacing.four)
                    .fill(
                        LinearGradient(
                            colors: [
                                MoruPilotColor.accent,
                                MoruPilotColor.accent.opacity(0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: max(4, 78 * completion.completionRate))
                    .opacity(completion.hasData ? 1 : 0)

                Text(historyWeekdayText(completion.date, calendar: calendar))
                    .historyOverviewTextStyle(.c1)
                    .foregroundStyle(MoruPilotColor.textTertiary)

                Text(
                    completion.hasData
                        ? "\(Int((completion.completionRate * 100).rounded()))%"
                        : "-"
                )
                    .historyOverviewTextStyle(.c1)
                    .foregroundStyle(MoruPilotColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!completion.hasData || action == nil)
        .accessibilityLabel(
            completionAccessibilityLabel
        )
        .accessibilityHint(
            completion.hasData && action != nil
                ? "날짜별 상세 화면으로 이동합니다"
                : completion.hasData
                    ? "계정 요약에는 날짜별 상세 기록이 없습니다"
                    : "기록이 없습니다"
        )
    }

    private var completionAccessibilityLabel: String {
        let weekday = historyWeekdayText(completion.date, calendar: calendar)
        guard completion.hasData else {
            return "\(weekday)요일 기록 없음"
        }

        return "\(weekday)요일 완수율 "
          + "\(Int((completion.completionRate * 100).rounded()))퍼센트"
    }
}

struct HistoryInlineEmptyCard: View {
    let message: String

    var body: some View {
        Text(message)
            .historyOverviewTextStyle(.b4)
            .foregroundStyle(MoruPilotColor.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 76)
            .padding(.horizontal, MoruPilotSpacing.sixteen)
            .background(AppColor.grayWhite.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard))
            .shadow(color: MoruPilotColor.shadow, radius: 7.5, x: 0, y: 0)
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
            accessibilityLabel = "\(dateText), 완수율 "
            + "\(Int((completionRate * 100).rounded()))퍼센트"
        } else {
            accessibilityLabel = "\(dateText), 기록 없음"
        }
        isAccessibilityHidden = false
    }
}

struct HistoryMonthlyHeatmapView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let heatmap: HistoryMonthlyHeatmap
    let calendar: Calendar
    let onSelect: ((HistoryHeatmapDay) -> Void)?

    init(
        heatmap: HistoryMonthlyHeatmap,
        calendar: Calendar,
        onSelect: ((HistoryHeatmapDay) -> Void)? = nil
    ) {
        self.heatmap = heatmap
        self.calendar = calendar
        self.onSelect = onSelect
    }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: MoruPilotSpacing.four),
        count: 7
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HistoryPilotSectionHeader(title: "월간 히트맵")

            VStack(spacing: 0) {
                Text(monthText)
                    .historyOverviewTextStyle(.b4)
                    .foregroundStyle(AppColor.gray400)
                    .frame(maxWidth: .infinity, minHeight: 40)

                VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 16 : 12) {
                    LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(
                        ["일", "월", "화", "수", "목", "금", "토"],
                        id: \.self
                    ) { weekday in
                        Text(weekday)
                            .historyOverviewTextStyle(.c1)
                            .foregroundStyle(AppColor.gray400)
                            .lineLimit(1)
                            .minimumScaleFactor(0.45)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: heatmapCellHeight
                            )
                            .accessibilityLabel("\(weekday)요일")
                            .accessibilityAddTraits(.isHeader)
                    }
                    }

                    LazyVGrid(
                        columns: columns,
                        spacing: dynamicTypeSize.isAccessibilitySize ? 8 : 6
                    ) {
                        ForEach(heatmap.days) { day in
                            let presentation = HistoryHeatmapCellPresentation(
                                day: day,
                                calendar: calendar
                            )

                            if isSelectable(day) {
                                Button {
                                    onSelect?(day)
                                } label: {
                                    heatmapCell(day)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    presentation.accessibilityLabel ?? ""
                                )
                                .accessibilityHint("데일리 리포트를 엽니다.")
                            } else {
                                heatmapCell(day)
                                    .accessibilityLabel(
                                        presentation.accessibilityLabel ?? ""
                                    )
                                    .accessibilityHidden(
                                        presentation.isAccessibilityHidden
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, MoruPilotSpacing.twenty)
                .padding(.top, dynamicTypeSize.isAccessibilitySize ? 20 : 24)
                .padding(.bottom, MoruPilotSpacing.eight)
                .frame(maxWidth: .infinity, minHeight: 212, alignment: .top)
                .background(historyPilotSurface)
                .clipShape(RoundedRectangle(cornerRadius: MoruPilotSpacing.twelve))
            }
            .padding(.top, MoruPilotSpacing.eight)
            .padding(.bottom, MoruPilotSpacing.twenty)
            .frame(maxWidth: .infinity, minHeight: 284, alignment: .top)
            .background(historyPilotSurface)
            .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard))
            .shadow(
                color: MoruPilotColor.shadow,
                radius: 15,
                x: 0,
                y: 0
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.heatmap")
    }

    private var monthText: String {
        let year = calendar.component(.year, from: heatmap.monthStartDate)
        let month = calendar.component(.month, from: heatmap.monthStartDate)
        return "\(year)년 \(month)월"
    }

    private var heatmapCellHeight: CGFloat {
        onSelect != nil || dynamicTypeSize.isAccessibilitySize ? 44 : 24
    }

    private func isSelectable(_ day: HistoryHeatmapDay) -> Bool {
        onSelect != nil
          && day.date != nil
          && day.completionRate != nil
    }

    private func heatmapCell(_ day: HistoryHeatmapDay) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: MoruPilotSpacing.eight)
                .fill(fillColor(for: day.bucket))

            if let date = day.date {
                Text("\(calendar.component(.day, from: date))")
                    .historyOverviewTextStyle(.c2)
                    .foregroundStyle(AppColor.gray500)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
            }
        }
        .frame(height: heatmapCellHeight)
    }

    private func fillColor(for bucket: HistoryHeatmapBucket) -> Color {
        switch bucket {
        case .noData:
            return MoruPilotColor.accentSurface
        case .zero:
            return MoruPilotColor.accentTint
        case .low:
            return Color(red: 1, green: 211 / 255, blue: 189 / 255)
        case .high:
            return MoruPilotColor.accentSoft
        case .complete:
            return MoruPilotColor.accent
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let index: Int
    let title: String
    let resultText: String
    let isCompleted: Bool

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: MoruPilotSpacing.twelve) {
                    HStack(alignment: .top, spacing: MoruPilotSpacing.twelve) {
                        completionIcon
                        titleText
                    }

                    resultBadge
                        .padding(.leading, 30)
                }
            } else {
                HStack(spacing: MoruPilotSpacing.eight) {
                    completionIcon
                    titleText
                    Spacer(minLength: MoruPilotSpacing.eight)
                    resultBadge
                }
            }
        }
        .padding(.horizontal, MoruPilotSpacing.sixteen)
        .padding(.vertical, MoruPilotSpacing.twelve)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(historyPilotSurface)
        .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard))
        .shadow(color: MoruPilotColor.shadow, radius: 7.5, x: 0, y: 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(index)번째, \(title), \(resultText)")
    }

    private var completionIcon: some View {
        ZStack {
            Circle()
                .stroke(
                    isCompleted
                        ? Color(red: 117 / 255, green: 161 / 255, blue: 1)
                        : MoruPilotColor.textTertiary,
                    lineWidth: 1
                )
                .frame(width: 18, height: 18)

            Image(systemName: isCompleted ? "checkmark" : "minus")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(
                    isCompleted
                        ? Color(red: 117 / 255, green: 161 / 255, blue: 1)
                        : MoruPilotColor.textTertiary
                )
        }
        .accessibilityHidden(true)
    }

    private var titleText: some View {
        Text(title)
            .historyOverviewTextStyle(.b4.weight(.semiBold))
            .foregroundStyle(MoruPilotColor.textStrong)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var resultBadge: some View {
        Text(resultText)
            .historyOverviewTextStyle(.c1)
            .foregroundStyle(
                isCompleted
                    ? MoruPilotColor.textPrimary
                    : MoruPilotColor.textSecondary
            )
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct HistoryLoadingView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("이력")
                    .historyOverviewTextStyle(.h3)
                    .foregroundStyle(AppColor.gray550)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)

                VStack(alignment: .leading, spacing: MoruPilotSpacing.thirtyTwo) {
                    HistorySkeletonBlock(cornerRadius: MoruPilotRadius.largeCard)
                        .frame(height: 114)
                        .padding(.vertical, MoruPilotSpacing.eight)

                    skeletonSection(cardHeight: 111)
                    heatmapSkeleton
                }
            }
            .padding(.horizontal, MoruPilotSpacing.twenty)
            .padding(.bottom, MoruPilotSpacing.sixtyFour)
        }
        .accessibilityLabel(HistoryCopy.loadingAccessibilityLabel)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func skeletonSection(cardHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HistorySkeletonBlock(cornerRadius: MoruPilotRadius.card)
                .frame(width: 90, height: 22)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)

            HistorySkeletonBlock(cornerRadius: MoruPilotRadius.largeCard)
                .frame(height: cardHeight)
                .padding(.vertical, MoruPilotSpacing.eight)
        }
    }

    private var heatmapSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            HistorySkeletonBlock(cornerRadius: MoruPilotRadius.card)
                .frame(width: 90, height: 22)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)

            VStack(spacing: 0) {
                HistorySkeletonBlock(cornerRadius: MoruPilotRadius.card)
                    .frame(width: 160, height: 24)
                    .frame(maxWidth: .infinity, minHeight: 40)

                HistorySkeletonBlock(cornerRadius: MoruPilotSpacing.twelve)
                    .frame(height: 212)
            }
            .padding(.top, MoruPilotSpacing.eight)
            .padding(.bottom, MoruPilotSpacing.twenty)
            .frame(maxWidth: .infinity, minHeight: 284, alignment: .top)
        }
    }
}

struct HistoryEmptyView: View {
    let title: String
    let message: String

    var body: some View {
        HistoryStatusView(
            systemImage: "calendar.badge.clock",
            title: title,
            message: message
        )
    }
}

struct HistoryFailureView: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        HistoryStatusView(
            systemImage: "exclamationmark.triangle.fill",
            title: message,
            message: HistoryCopy.retryLater,
            primaryActionTitle: HistoryCopy.retry,
            primaryAction: retryAction
        )
    }
}

struct HistoryStatusView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let systemImage: String
    let title: String
    let message: String
    var primaryActionTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: MoruPilotSpacing.sixteen) {
                    Image(systemName: systemImage)
                        .font(AppFont.title1SemiBold)
                        .foregroundStyle(MoruPilotColor.accent)
                        .accessibilityHidden(true)

                    Text(title)
                        .historyOverviewTextStyle(.h3)
                        .foregroundStyle(MoruPilotColor.textStrong)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .historyOverviewTextStyle(.b4)
                        .foregroundStyle(MoruPilotColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if let primaryActionTitle, let primaryAction {
                        if dynamicTypeSize.isAccessibilitySize {
                            Button(action: primaryAction) {
                                Text(primaryActionTitle)
                                    .historyOverviewTextStyle(.b4.weight(.semiBold))
                                    .foregroundStyle(MoruPilotColor.textStrong)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, MoruPilotSpacing.twenty)
                                    .padding(.vertical, MoruPilotSpacing.sixteen)
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .background(AppColor.grayWhite)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            MoruButton(
                                primaryActionTitle,
                                style: .secondary,
                                componentStyle: .figmaPilot,
                                action: primaryAction
                            )
                        }
                    }

                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .historyOverviewTextStyle(.b4.weight(.semiBold))
                            .foregroundStyle(MoruPilotColor.textPrimary)
                            .buttonStyle(.plain)
                            .frame(minHeight: 44)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: proxy.size.height,
                    alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center
                )
                .padding(.horizontal, MoruPilotSpacing.twenty)
                .padding(.vertical, MoruPilotSpacing.thirtyTwo)
            }
        }
    }
}

private struct HistorySkeletonBlock: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        AppColor.gray150.opacity(0.5),
                        AppColor.gray250.opacity(0.5),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .accessibilityHidden(true)
    }
}

private struct HistoryOverviewTextStyleModifier: ViewModifier {
    let style: MoruTextStyle

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            content.font(
                .custom(
                    style.weight.rawValue,
                    size: style.fontSize,
                    relativeTo: style.relativeTextStyle
                )
            )
        } else {
            content.moruTextStyle(style)
        }
    }
}

extension View {
    func historyOverviewTextStyle(_ style: MoruTextStyle) -> some View {
        modifier(HistoryOverviewTextStyleModifier(style: style))
    }
}

func historyWeekdayText(_ date: Date, calendar: Calendar) -> String {
    let symbols = ["일", "월", "화", "수", "목", "금", "토"]
    let weekday = calendar.component(.weekday, from: date)
    return symbols[max(0, min(weekday - 1, symbols.count - 1))]
}
