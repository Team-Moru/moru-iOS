//
//  HistoryView.swift
//  Moru
//
//  Created by Codex on 7/14/26.
//

import Foundation
import SwiftUI

struct HistoryRunDetailDestinationPresentation: Equatable {
  let run: HistoryRun
  let calendar: Calendar
}

enum HistoryRunDetailDestinationResolution: Equatable {
  case noPendingDestination
  case selected(HistoryRunDetailDestinationPresentation)
  case missing
}

@MainActor
enum HistoryRunDetailDestinationResolver {
  static func resolve(
    destination: HistoryDestination?,
    in overview: HistoryOverview
  ) -> HistoryRunDetailDestinationResolution {
    guard let destination else {
      return .noPendingDestination
    }

    switch destination {
    case .runDetail(let runID):
      let matchingRuns = overview.recentDays
        .flatMap(\.runs)
        .filter { $0.id == runID }

      guard matchingRuns.count == 1, let run = matchingRuns.first else {
        return .missing
      }

      return .selected(
        HistoryRunDetailDestinationPresentation(
          run: run,
          calendar: overview.calendar
        )
      )
    }
  }
}

struct HistoryView: View {
  static let rootAccessibilityIdentifier = "history.root"

  @State private var viewModel: HistoryViewModel
  @State private var isWeeklyReportPresented = false
  @Binding private var pendingDestination: HistoryDestination?
  @State private var selectedRun: HistoryRun?
  @State private var selectedRunCalendar: Calendar?
  @State private var selectedDay: HistoryDaySummary?
  @State private var selectedDayCalendar: Calendar?
  @State private var isDestinationMissing = false

  init(
    viewModel: HistoryViewModel,
    destination: Binding<HistoryDestination?> = .constant(nil)
  ) {
    _viewModel = State(initialValue: viewModel)
    _pendingDestination = destination
  }

  var body: some View {
    NavigationStack {
      Group {
        switch viewModel.state {
        case .loading:
          HistoryLoadingView()
        case .content(let overview):
          if isDestinationMissing {
            HistoryDestinationMissingView(
              retryAction: retryPendingDestination,
              backAction: dismissMissingDestination
            )
          } else {
            overviewContent(overview)
              .onAppear {
                resolvePendingDestination(in: overview)
              }
          }
        case .empty:
          if pendingDestination == nil {
            HistoryEmptyView(
              title: "아직 기록이 없어요.",
              message:
                "루틴을 완료하면 이곳에서 매일의 기록과 "
                + "주간 리포트를 확인할 수 있어요."
            )
          } else {
            HistoryDestinationMissingView(
              retryAction: retryPendingDestination,
              backAction: dismissMissingDestination
            )
          }
        case .failed(let message):
          HistoryFailureView(
            message: message,
            retryAction: viewModel.retryButtonDidTap
          )
        }
      }
      .background(AppColor.grayWhite.ignoresSafeArea())
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(isPresented: $isWeeklyReportPresented) {
        if case .content(let overview) = viewModel.state {
          HistoryWeeklyReportView(overview: overview)
        }
      }
      .navigationDestination(isPresented: isRunDetailPresented) {
        if let selectedRun, let selectedRunCalendar {
          HistoryRunDetailView(run: selectedRun, calendar: selectedRunCalendar)
        }
      }
      .navigationDestination(isPresented: isDayDetailPresented) {
        if let selectedDay, let selectedDayCalendar {
          HistoryDailyDetailView(day: selectedDay, calendar: selectedDayCalendar)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(Self.rootAccessibilityIdentifier)
    .accessibilityLabel("이력")
    .task {
      viewModel.load()
      resolveLoadedDestination()
    }
    .onChange(of: pendingDestination) { _, destination in
      guard destination != nil else {
        return
      }

      resolveLoadedDestination()
    }
  }

  private func overviewContent(_ overview: HistoryOverview) -> some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: AppSpacing.md) {
        Text("이력")
          .font(AppFont.pretendardBold(size: 26))
          .foregroundStyle(AppColor.grayBlack)
          .padding(.top, AppSpacing.sm)

        HistoryStreakCard(
          currentStreak: overview.currentCompletionStreak,
          bestStreak: overview.bestCompletionStreak
        )

        HistoryWakeMetricsView(metrics: overview.wakeMetrics)
        HistoryWeeklyCompletionChart(
          completions: overview.week.dailyCompletionRates,
          calendar: overview.calendar,
          onSelect: { completion in
            selectDay(for: completion.date, in: overview)
          }
        )
        HistoryMonthlyHeatmapView(
          heatmap: overview.monthlyHeatmap,
          calendar: overview.calendar
        )

        HistorySectionHeader(
          title: "주간 리포트",
          actionTitle: "자세히",
          action: { isWeeklyReportPresented = true }
        )

        HistoryWeeklyInsightCard(
          completionRate: overview.week.completionRate,
          calendar: overview.calendar,
          day: overview.lowestCompletionDay
        )

        HistorySectionHeader(title: "최근 기록", actionTitle: nil, action: nil)

        LazyVStack(spacing: AppSpacing.sm) {
          ForEach(overview.recentDays, id: \.date) { day in
            NavigationLink {
              HistoryDailyDetailView(day: day, calendar: overview.calendar)
            } label: {
              HistoryDaySummaryRow(day: day, calendar: overview.calendar)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .padding(.horizontal, AppSpacing.screenHorizontal)
      .padding(.top, AppSpacing.xs)
      .padding(.bottom, AppSpacing.xxl)
    }
  }

  private var isRunDetailPresented: Binding<Bool> {
    Binding(
      get: { selectedRun != nil },
      set: { isPresented in
        guard !isPresented else {
          return
        }

        selectedRun = nil
        selectedRunCalendar = nil
      }
    )
  }

  private var isDayDetailPresented: Binding<Bool> {
    Binding(
      get: { selectedDay != nil },
      set: { isPresented in
        guard !isPresented else {
          return
        }

        selectedDay = nil
        selectedDayCalendar = nil
      }
    )
  }

  private func selectDay(for date: Date, in overview: HistoryOverview) {
    guard let day = overview.daySummary(for: date) else {
      return
    }

    selectedDay = day
    selectedDayCalendar = overview.calendar
  }

  private func resolveLoadedDestination() {
    switch viewModel.state {
    case .content(let overview):
      resolvePendingDestination(in: overview)
    case .empty:
      isDestinationMissing = pendingDestination != nil
    case .loading, .failed:
      break
    }
  }

  private func resolvePendingDestination(in overview: HistoryOverview) {
    switch HistoryRunDetailDestinationResolver.resolve(
      destination: pendingDestination,
      in: overview
    ) {
    case .noPendingDestination:
      return
    case .selected(let presentation):
      pendingDestination = nil
      selectedRun = presentation.run
      selectedRunCalendar = presentation.calendar
      isDestinationMissing = false
    case .missing:
      isDestinationMissing = true
    }
  }

  private func retryPendingDestination() {
    isDestinationMissing = false
    viewModel.load()
    resolveLoadedDestination()
  }

  private func dismissMissingDestination() {
    pendingDestination = nil
    isDestinationMissing = false
  }
}

private func historyWeekRangeText(
  from startDate: Date,
  toExclusive endDate: Date,
  calendar: Calendar
) -> String {
  let finalDate = calendar.date(byAdding: .day, value: -1, to: endDate) ?? endDate
  let format = Date.FormatStyle.dateTime.month(.wide).day()
  let startText = historyFormattedDate(startDate, calendar: calendar, format: format)
  let endText = historyFormattedDate(finalDate, calendar: calendar, format: format)

  return "\(startText) ~ \(endText)"
}

private func historyFormattedDate(
  _ date: Date,
  calendar: Calendar,
  format: Date.FormatStyle
) -> String {
  var configuredFormat = format
  configuredFormat.calendar = calendar
  configuredFormat.timeZone = calendar.timeZone
  configuredFormat.locale = calendar.locale ?? .autoupdatingCurrent
  return date.formatted(configuredFormat)
}

private extension HistoryOverview {
  var currentCompletionStreak: Int {
    recentDays
      .sorted { $0.date > $1.date }
      .prefix { $0.completionRate > 0 }
      .count
  }

  var bestCompletionStreak: Int {
    let sortedDays = recentDays.sorted { $0.date < $1.date }
    var current = 0
    var best = 0

    for day in sortedDays {
      if day.completionRate > 0 {
        current += 1
        best = max(best, current)
      } else {
        current = 0
      }
    }

    return best
  }

  var lowestCompletionDay: HistoryDailyCompletion? {
    week.dailyCompletionRates
      .filter { $0.completionRate > 0 }
      .min { $0.completionRate < $1.completionRate }
  }

  func daySummary(for date: Date) -> HistoryDaySummary? {
    recentDays.first { day in
      calendar.isDate(day.date, inSameDayAs: date)
    }
  }

  var weeklyStepAnalysisItems: [HistoryStepAnalysisItem] {
    let weekRuns = recentDays
      .flatMap(\.runs)
      .filter { run in
        run.startedAt >= week.weekStartDate && run.startedAt < week.weekEndDate
      }
    let stepGroups = Dictionary(grouping: weekRuns.flatMap(\.stepResults)) { result in
      result.stepTitle
    }

    return stepGroups
      .map { title, results in
        let completedCount = results.filter(\.isCompleted).count
        let totalCount = results.count

        return HistoryStepAnalysisItem(
          title: title,
          completedCount: completedCount,
          totalCount: totalCount
        )
      }
      .sorted {
        if $0.completionRate != $1.completionRate {
          return $0.completionRate > $1.completionRate
        }

        return $0.title < $1.title
      }
  }
}

private struct HistoryStreakCard: View {
  let currentStreak: Int
  let bestStreak: Int

  var body: some View {
    HStack(alignment: .center, spacing: AppSpacing.md) {
      Text("\(currentStreak)")
        .font(AppFont.pretendardBold(size: 38))
        .foregroundStyle(AppColor.grayWhite)
        .frame(width: 42, alignment: .center)

      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text("일 연속 달성")
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.gray400)

        Text("최고 기록: \(max(bestStreak, currentStreak))일")
          .font(AppFont.pretendardRegular(size: 11))
          .foregroundStyle(AppColor.gray500)
      }

      Spacer()

      Text("🔥")
        .font(.system(size: 22))
    }
    .padding(.horizontal, AppSpacing.lg)
    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
    .background(AppColor.grayBlack)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
  }
}

private struct HistoryWeeklyInsightCard: View {
  let completionRate: Double
  let calendar: Calendar
  let day: HistoryDailyCompletion?

  var body: some View {
    VStack(spacing: AppSpacing.sm) {
      Text(insightText)
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.grayWhite)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
    .padding(AppSpacing.lg)
    .frame(maxWidth: .infinity, minHeight: 90)
    .background(AppColor.grayBlack)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
    .accessibilityLabel(insightText)
  }

  private var insightText: String {
    guard let day else {
      return "이번 주 루틴 기록을 쌓고 있어요"
    }

    let weekday = historyWeekdayText(day.date, calendar: calendar)
    let totalRate = Int((completionRate * 100).rounded())
    return "\(weekday)요일이 가장 완수율이 떨어지고,\n이번 주 평균은 \(totalRate)%예요"
  }
}

private extension HistoryDaySummary {
  var stepResults: [HistoryStepResult] {
    runs.flatMap(\.stepResults)
  }

  var recordedStepResults: [HistoryStepResult] {
    let recorded = stepResults.filter { result in
      if let transcript = result.transcript {
        return !transcript.isEmpty
      }

      return result.isSkipped
    }

    return recorded.isEmpty ? stepResults.filter(\.isSkipped) : recorded
  }

  var firstRun: HistoryRun? {
    runs.sorted { $0.startedAt < $1.startedAt }.first
  }

  func elapsedText(calendar: Calendar) -> String {
    guard let firstRun, let completedAt = firstRun.completedAt else {
      return "--:--"
    }

    let seconds = max(0, Int(completedAt.timeIntervalSince(firstRun.startedAt)))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }
}

private struct HistoryDailySummaryCard: View {
  let day: HistoryDaySummary
  let calendar: Calendar

  var body: some View {
    HStack(spacing: AppSpacing.md) {
      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text("완수율")
          .font(AppFont.pretendardRegular(size: 10))
          .foregroundStyle(AppColor.gray400)

        Text("\(Int((day.completionRate * 100).rounded()))%")
          .font(AppFont.pretendardBold(size: 32))
          .foregroundStyle(AppColor.grayWhite)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      HistorySummaryDivider()

      HistoryDailyMetric(title: "기상 시각", value: wakeText, detail: "첫 루틴 시작")

      HistorySummaryDivider()

      HistoryDailyMetric(title: "소요 시간", value: day.elapsedText(calendar: calendar), detail: "실행 기준")
    }
    .padding(AppSpacing.sm)
    .frame(maxWidth: .infinity, minHeight: 86)
    .background(AppColor.grayBlack)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
  }

  private var wakeText: String {
    guard let firstRun = day.firstRun else {
      return "--:--"
    }

    return historyFormattedDate(
      firstRun.startedAt,
      calendar: calendar,
      format: Date.FormatStyle(date: .omitted, time: .shortened)
    )
  }
}

private struct HistorySummaryDivider: View {
  var body: some View {
    Rectangle()
      .fill(AppColor.gray650)
      .frame(width: 1, height: 54)
  }
}

private struct HistoryDailyMetric: View {
  let title: String
  let value: String
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
      Text(title)
        .font(AppFont.pretendardRegular(size: 10))
        .foregroundStyle(AppColor.gray500)

      Text(value)
        .font(AppFont.pretendardBold(size: 16))
        .foregroundStyle(AppColor.grayWhite)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      Text(detail)
        .font(AppFont.pretendardRegular(size: 10))
        .foregroundStyle(AppColor.gray550)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct HistoryRecordCard: View {
  let result: HistoryStepResult

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      Text(result.stepTitle)
        .font(AppFont.pretendardBold(size: 11))
        .foregroundStyle(AppColor.gray500)

      Divider()

      Text(recordText)
        .font(AppFont.caption1Medium)
        .foregroundStyle(AppColor.gray350)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(AppSpacing.sm)
    .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
    .background(AppColor.grayWhite)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
    .overlay {
      RoundedRectangle(cornerRadius: AppRadius.xs)
        .stroke(AppColor.moruBorder, lineWidth: 1)
    }
  }

  private var recordText: String {
    if let transcript = result.transcript, !transcript.isEmpty {
      return transcript
    }

    return result.isSkipped ? "건너뜀 - 기록 없음" : "기록 없음"
  }
}

private struct HistoryDaySummaryRow: View {
  let day: HistoryDaySummary
  let calendar: Calendar
  var body: some View {
    HStack(spacing: AppSpacing.md) {
      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text(historyFormattedDate(
          day.date,
          calendar: calendar,
          format: .dateTime.month().day().weekday(.wide)
        ))
          .font(AppFont.label1NormalMedium)
          .foregroundStyle(AppColor.grayBlack)

        HistoryCompletionRateBar(completionRate: day.completionRate)
      }

      Spacer()

      VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
        Text("\(Int((day.completionRate * 100).rounded()))%")
          .font(AppFont.caption1SemiBold)
          .foregroundStyle(AppColor.grayBlack)

        Text("\(day.completedRunCount)/\(day.totalRunCount) 완료")
          .font(AppFont.pretendardRegular(size: 11))
          .foregroundStyle(AppColor.gray500)
      }
    }
    .padding(AppSpacing.sm)
    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    .background(AppColor.grayWhite)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
    .overlay {
      RoundedRectangle(cornerRadius: AppRadius.xs)
        .stroke(AppColor.moruBorder, lineWidth: 1)
    }
  }
}

private struct HistoryDailyDetailView: View {
  let day: HistoryDaySummary
  let calendar: Calendar
  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: AppSpacing.md) {
        HistoryDailySummaryCard(day: day, calendar: calendar)

        HistorySectionHeader(title: "항목별 결과", actionTitle: nil, action: nil)

        LazyVStack(spacing: AppSpacing.sm) {
          ForEach(Array(day.stepResults.enumerated()), id: \.element.stepID) { index, result in
            HistoryStepResultRow(
              index: index + 1,
              title: result.stepTitle,
              resultText: result.displayText,
              isCompleted: result.isCompleted,
              transcript: nil
            )
          }
        }

        HistorySectionHeader(title: "오늘의 기록", actionTitle: nil, action: nil)

        VStack(spacing: AppSpacing.sm) {
          ForEach(day.recordedStepResults, id: \.stepID) { result in
            HistoryRecordCard(result: result)
          }
        }
      }
      .padding(.horizontal, AppSpacing.screenHorizontal)
      .padding(.top, AppSpacing.md)
      .padding(.bottom, AppSpacing.xxl)
    }
    .background(AppColor.grayWhite.ignoresSafeArea())
    .navigationTitle(historyFormattedDate(
      day.date,
      calendar: calendar,
      format: .dateTime.month().day().weekday(.wide)
    ))
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct HistoryRunDetailView: View {
  let run: HistoryRun
  let calendar: Calendar

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: AppSpacing.md) {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
          HistoryRunRow(
            routineName: run.routineName,
            timeText: historyFormattedDate(
              run.startedAt,
              calendar: calendar,
              format: Date.FormatStyle(date: .omitted, time: .shortened)
            ),
            completionText: run.status.displayText,
            isCompleted: run.status == .completed
          )

          HistoryCompletionRateBar(completionRate: run.completionRate)
        }
        .padding(AppSpacing.md)
        .background(AppColor.grayWhite)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
        .overlay {
          RoundedRectangle(cornerRadius: AppRadius.xs)
            .stroke(AppColor.moruBorder, lineWidth: 1)
        }

        HistorySectionHeader(title: "단계 기록", actionTitle: nil, action: nil)

        LazyVStack(spacing: AppSpacing.sm) {
          ForEach(Array(run.stepResults.enumerated()), id: \.element.stepID) { index, result in
            HistoryStepResultRow(
              index: index + 1,
              title: result.stepTitle,
              resultText: result.displayText,
              isCompleted: result.isCompleted,
              transcript: result.transcript
            )
          }
        }
      }
      .padding(.horizontal, AppSpacing.screenHorizontal)
      .padding(.top, AppSpacing.lg)
      .padding(.bottom, AppSpacing.xxl)
    }
    .background(AppColor.grayWhite.ignoresSafeArea())
    .navigationTitle("실행 기록")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("history.runDetail")
  }
}

private struct HistoryDestinationMissingView: View {
  let retryAction: () -> Void
  let backAction: () -> Void

  var body: some View {
    VStack(spacing: AppSpacing.md) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(AppFont.title1SemiBold)
        .foregroundStyle(AppColor.orange500)

      Text("실행 기록을 찾을 수 없어요.")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Text("요청한 실행 기록이 삭제되었거나 아직 저장되지 않았어요.")
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
        .multilineTextAlignment(.center)

      MoruButton("다시 시도", style: .secondary, action: retryAction)
      MoruButton("기록으로 돌아가기", style: .text, action: backAction)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(AppSpacing.xxl)
    .accessibilityIdentifier("history.runDetail.missing")
  }
}


private struct HistoryWeeklyReportView: View {
  let overview: HistoryOverview
  @State private var selectedDay: HistoryDaySummary?

  private var report: HistoryWeekReport {
    overview.week
  }

  private var calendar: Calendar {
    overview.calendar
  }

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: AppSpacing.md) {
        HistoryWeeklySummaryCard(
          title: weekRangeText,
          completedRuns: report.completedRunCount,
          totalRuns: report.totalRunCount,
          completionRate: report.completionRate,
          action: {}
        )

        HistoryWeeklyCompletionChart(
          completions: report.dailyCompletionRates,
          calendar: calendar,
          onSelect: { completion in
            selectedDay = overview.daySummary(for: completion.date)
          }
        )

        HistoryWeeklyStepAnalysisView(items: overview.weeklyStepAnalysisItems)
      }
      .padding(.horizontal, AppSpacing.screenHorizontal)
      .padding(.top, AppSpacing.md)
      .padding(.bottom, AppSpacing.xxl)
    }
    .background(AppColor.grayWhite.ignoresSafeArea())
    .navigationTitle(weekRangeText)
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(isPresented: isDayDetailPresented) {
      if let selectedDay {
        HistoryDailyDetailView(day: selectedDay, calendar: calendar)
      }
    }
  }

  private var isDayDetailPresented: Binding<Bool> {
    Binding(
      get: { selectedDay != nil },
      set: { isPresented in
        guard !isPresented else {
          return
        }

        selectedDay = nil
      }
    )
  }

  private var weekRangeText: String {
    historyWeekRangeText(
      from: report.weekStartDate,
      toExclusive: report.weekEndDate,
      calendar: calendar
    )
  }
}

private struct HistoryWeeklyDailyRateRow: View {
  let completion: HistoryDailyCompletion
  let calendar: Calendar
  var body: some View {
    HStack(spacing: AppSpacing.md) {
      Text(historyFormattedDate(
        completion.date,
        calendar: calendar,
        format: .dateTime.weekday(.abbreviated)
      ))
        .font(AppFont.label1NormalSemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)
        .frame(width: 28, alignment: .leading)

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(AppColor.moruSurfaceMuted)

          Capsule()
            .fill(AppColor.orange350)
            .frame(width: proxy.size.width * completion.completionRate)
        }
      }
      .frame(height: 8)

      Text("\(Int((completion.completionRate * 100).rounded()))%")
        .font(AppFont.caption1SemiBold)
        .foregroundStyle(AppColor.moruTextSecondary)
        .frame(width: 36, alignment: .trailing)
    }
    .padding(AppSpacing.md)
    .frame(maxWidth: .infinity)
    .background(AppColor.grayWhite)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    .overlay {
      RoundedRectangle(cornerRadius: AppRadius.md)
        .stroke(AppColor.moruBorder, lineWidth: 1)
    }
  }
}
