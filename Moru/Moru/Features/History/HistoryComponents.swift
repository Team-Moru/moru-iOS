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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let completedRuns: Int
    let totalRuns: Int
    let completionRate: Double
    let completionRateChangePercentagePoints: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("이번 주 리포트")
                            .font(AppFont.caption1Medium)
                            .foregroundStyle(AppColor.gray400)

                        Text(title)
                            .font(AppFont.caption1Medium)
                            .foregroundStyle(AppColor.gray500)

                        Text("\(Int((completionRate * 100).rounded()))%")
                            .font(AppFont.pretendardBold(size: 30))
                            .foregroundStyle(AppColor.grayWhite)

                        Text("\(completedRuns)/\(max(totalRuns, 1))회 완료")
                            .font(AppFont.caption1SemiBold)
                            .foregroundStyle(AppColor.grayWhite)

                        Text(comparisonText)
                            .font(AppFont.pretendardRegular(size: 10))
                            .foregroundStyle(AppColor.gray500)
                    }
                } else {
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

                            Text(comparisonText)
                                .font(AppFont.pretendardRegular(size: 10))
                                .foregroundStyle(AppColor.gray500)
                        }
                    }
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
            + "완수율 \(Int((completionRate * 100).rounded()))퍼센트, "
            + comparisonAccessibilityText
        )
    }

    private var comparisonText: String {
        guard let change = completionRateChangePercentagePoints else {
            return "지난주 대비 —"
        }

        let prefix = change > 0 ? "+" : ""
        return "지난주 대비 \(prefix)\(change)%p"
    }

    private var comparisonAccessibilityText: String {
        guard let change = completionRateChangePercentagePoints else {
            return "지난주 비교 데이터 없음"
        }

        return "지난주 대비 \(change)퍼센트포인트"
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

private var historyPilotSurface: Color {
    AppColor.grayWhite.opacity(0.2)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let heatmap: HistoryMonthlyHeatmap
    let calendar: Calendar

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
                            .accessibilityLabel(presentation.accessibilityLabel ?? "")
                            .accessibilityHidden(presentation.isAccessibilityHidden)
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
        dynamicTypeSize.isAccessibilitySize ? 44 : 24
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
        .accessibilityLabel("기록을 불러오는 중이에요.")
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
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: MoruPilotSpacing.sixteen) {
                    Image(systemName: "calendar.badge.clock")
                        .font(AppFont.title1SemiBold)
                        .foregroundStyle(MoruPilotColor.accent)

                    Text(title)
                        .historyOverviewTextStyle(.h3)
                        .foregroundStyle(MoruPilotColor.textStrong)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .historyOverviewTextStyle(.b4)
                        .foregroundStyle(MoruPilotColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .padding(.horizontal, MoruPilotSpacing.twenty)
                .padding(.vertical, MoruPilotSpacing.thirtyTwo)
            }
        }
    }
}

struct HistoryFailureView: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: MoruPilotSpacing.sixteen) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppFont.title1SemiBold)
                        .foregroundStyle(MoruPilotColor.accent)

                    Text(message)
                        .historyOverviewTextStyle(.h3)
                        .foregroundStyle(MoruPilotColor.textStrong)
                        .multilineTextAlignment(.center)

                    Text("잠시 후 다시 시도해 주세요.")
                        .historyOverviewTextStyle(.b4)
                        .foregroundStyle(MoruPilotColor.textSecondary)
                        .multilineTextAlignment(.center)

                    HistoryRetryButton(action: retryAction)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .padding(.horizontal, MoruPilotSpacing.twenty)
                .padding(.vertical, MoruPilotSpacing.thirtyTwo)
            }
        }
    }
}

private struct HistoryRetryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("다시 시도")
                .historyOverviewTextStyle(.b4.weight(.semiBold))
                .foregroundStyle(MoruPilotColor.textStrong)
                .padding(.horizontal, AppSpacing.buttonHorizontal)
                .padding(.vertical, AppSpacing.buttonVertical)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(AppColor.grayWhite)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
        }
        .buttonStyle(.plain)
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
