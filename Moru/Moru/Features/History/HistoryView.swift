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
  private let automaticallyLoads: Bool

  init(
    viewModel: HistoryViewModel,
    destination: Binding<HistoryDestination?> = .constant(nil),
    automaticallyLoads: Bool = true
  ) {
    _viewModel = State(initialValue: viewModel)
    _pendingDestination = destination
    self.automaticallyLoads = automaticallyLoads
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
              title: HistoryCopy.noHistoryTitle,
              message: HistoryCopy.noHistoryMessage
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
      .background(MoruPilotColor.canvas.ignoresSafeArea())
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
      guard automaticallyLoads else {
        return
      }

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
      VStack(alignment: .leading, spacing: 0) {
        Text(HistoryCopy.overviewTitle)
          .historyOverviewTextStyle(.h3)
          .foregroundStyle(AppColor.gray550)
          .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)

        VStack(alignment: .leading, spacing: MoruPilotSpacing.thirtyTwo) {
          HistoryStreakWeeklyCard(
            streak: overview.streak,
            action: { isWeeklyReportPresented = true }
          )

          HistoryWakeMetricsView(metrics: overview.wakeMetrics)
          HistoryMonthlyHeatmapView(
            heatmap: overview.monthlyHeatmap,
            calendar: overview.calendar
          )

          HistoryWeeklyCompletionChart(
            completions: overview.week.dailyCompletionRates,
            calendar: overview.calendar,
            onSelect: { completion in
              selectDay(for: completion.date, in: overview)
            }
          )

          VStack(alignment: .leading, spacing: MoruPilotSpacing.sixteen) {
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
        }
      }
      .padding(.horizontal, MoruPilotSpacing.twenty)
      .padding(.bottom, MoruPilotSpacing.sixtyFour)
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

private func historyElapsedText(
  startedAt: Date,
  completedAt: Date?
) -> String {
  guard let completedAt else {
    return "--:--"
  }

  let seconds = max(0, Int(completedAt.timeIntervalSince(startedAt)))
  return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

private extension HistoryOverview {
  func daySummary(for date: Date) -> HistoryDaySummary? {
    recentDays.first { day in
      calendar.isDate(day.date, inSameDayAs: date)
    }
  }

  var weeklyStepAnalysisItems: [HistoryStepAnalysisItem] {
    let weekRuns = runsInCurrentWeek
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

  var weeklyAverageElapsedText: String {
    let durations = runsInCurrentWeek.compactMap { run -> Int? in
      guard let completedAt = run.completedAt else {
        return nil
      }

      return max(0, Int(completedAt.timeIntervalSince(run.startedAt)))
    }

    guard !durations.isEmpty else {
      return "--:--"
    }

    let averageSeconds = durations.reduce(0, +) / durations.count
    return String(
      format: "%02d:%02d",
      averageSeconds / 60,
      averageSeconds % 60
    )
  }

  private var runsInCurrentWeek: [HistoryRun] {
    recentDays
      .flatMap(\.runs)
      .filter { run in
        run.startedAt >= week.weekStartDate && run.startedAt < week.weekEndDate
      }
  }
}

private struct HistoryStreakWeeklyCard: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let streak: RoutineStreak
  let action: () -> Void

  private let weekdays: [(weekday: Weekday, label: String)] = [
    (.monday, "월"),
    (.tuesday, "화"),
    (.wednesday, "수"),
    (.thursday, "목"),
    (.friday, "금"),
    (.saturday, "토"),
    (.sunday, "일"),
  ]

  var body: some View {
    Button(action: action) {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: MoruPilotSpacing.twenty) {
            streakSummary
            Divider()
              .overlay(AppColor.orange150)
            weeklySummary
          }
          .padding(MoruPilotSpacing.twenty)
        } else {
          HStack(spacing: MoruPilotSpacing.sixteen) {
            streakSummary
              .frame(width: 91)

            Rectangle()
              .fill(AppColor.orange150)
              .frame(width: 1, height: 74)

            weeklySummary
          }
          .padding(.horizontal, MoruPilotSpacing.twenty)
          .frame(height: 114)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(historyStreakBackground)
      .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard))
    }
    .buttonStyle(.plain)
    .padding(.vertical, MoruPilotSpacing.eight)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "연속 달성 \(streak.currentDays)일째, "
      + "최고 기록 \(max(streak.bestDays, streak.currentDays))일, "
      + "이번 주 \(streak.completedWeekdays.count)일 완료"
    )
    .accessibilityHint("주간 리포트를 엽니다")
  }

  private var streakSummary: some View {
    VStack(spacing: 0) {
      Text("연속 달성")
        .historyOverviewTextStyle(.c2)
        .foregroundStyle(MoruPilotColor.accentSurface)

      Text("\(streak.currentDays)일째")
        .historyOverviewTextStyle(.h1.weight(.bold))
        .foregroundStyle(AppColor.grayWhite)

      Text("최고 기록 \(max(streak.bestDays, streak.currentDays))일")
        .font(AppFont.pretendardMedium(size: 10))
        .foregroundStyle(MoruPilotColor.textSecondary)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        .minimumScaleFactor(0.75)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, MoruPilotSpacing.sixteen)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 6 : 0)
        .frame(minHeight: MoruPilotSpacing.twenty)
        .background(MoruPilotColor.accentTint)
        .clipShape(Capsule())
    }
    .frame(maxWidth: .infinity)
  }

  private var weeklySummary: some View {
    VStack(spacing: 0) {
      Text(HistoryCopy.weeklyReportTitle)
        .historyOverviewTextStyle(.c2)
        .foregroundStyle(MoruPilotColor.accentSurface)

      Group {
        if dynamicTypeSize.isAccessibilitySize {
          LazyVGrid(
            columns: [
              GridItem(
                .adaptive(minimum: 88),
                spacing: MoruPilotSpacing.twelve
              ),
            ],
            spacing: MoruPilotSpacing.twelve
          ) {
            ForEach(weekdays, id: \.weekday) { item in
              weekdayStatus(
                weekday: item.weekday,
                label: item.label,
                isAccessibilityLayout: true
              )
            }
          }
        } else {
          HStack(spacing: MoruPilotSpacing.eight) {
            ForEach(weekdays, id: \.weekday) { item in
              weekdayStatus(
                weekday: item.weekday,
                label: item.label,
                isAccessibilityLayout: false
              )
            }
          }
        }
      }
      .padding(.top, MoruPilotSpacing.twelve)
    }
    .frame(maxWidth: .infinity)
  }

  private func weekdayStatus(
    weekday: Weekday,
    label: String,
    isAccessibilityLayout: Bool
  ) -> some View {
    let isCompleted = streak.completedWeekdays.contains(weekday)

    return VStack(spacing: MoruPilotSpacing.four) {
      ZStack {
        Circle()
          .fill(
            isCompleted
              ? MoruPilotColor.accent
              : MoruPilotColor.shadow
          )

        if isCompleted {
          Image(systemName: "checkmark")
            .font(.system(
              size: isAccessibilityLayout ? 14 : 10,
              weight: .bold
            ))
            .foregroundStyle(AppColor.grayWhite)
        }
      }
      .frame(
        width: isAccessibilityLayout ? 32 : MoruPilotSpacing.twenty,
        height: isAccessibilityLayout ? 32 : MoruPilotSpacing.twenty
      )

      Text(label)
        .historyOverviewTextStyle(.c2.weight(.regular))
        .foregroundStyle(MoruPilotColor.accentSurface)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(
      width: isAccessibilityLayout ? nil : MoruPilotSpacing.twenty
    )
  }

  private var historyStreakBackground: Color {
    MoruPilotColor.summarySurface
  }
}

private extension HistoryDaySummary {
  var stepResults: [HistoryStepResult] {
    runs.flatMap(\.stepResults)
  }

  var recordedStepResults: [HistoryStepResult] {
    stepResults.filter { result in
      guard let transcript = result.transcript else {
        return false
      }

      return !transcript.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
    }
  }

  var firstRun: HistoryRun? {
    runs.sorted { $0.startedAt < $1.startedAt }.first
  }

  func elapsedText(calendar: Calendar) -> String {
    guard let firstRun else {
      return "--:--"
    }

    return historyElapsedText(
      startedAt: firstRun.startedAt,
      completedAt: firstRun.completedAt
    )
  }
}

private extension HistoryRun {
  var elapsedText: String {
    historyElapsedText(
      startedAt: startedAt,
      completedAt: completedAt
    )
  }

  var recordedStepResults: [HistoryStepResult] {
    stepResults.filter { result in
      guard let transcript = result.transcript else {
        return false
      }

      return !transcript.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
    }
  }
}

private struct HistoryDailySummaryCard: View {
  let day: HistoryDaySummary
  let calendar: Calendar

  var body: some View {
    HistoryReportSummaryCard(
      metrics: [
        HistoryReportMetric(
          title: HistoryCopy.completionRate,
          value: "\(Int((day.completionRate * 100).rounded()))%",
          systemImage: "checkmark"
        ),
        HistoryReportMetric(
          title: HistoryCopy.duration,
          value: day.elapsedText(calendar: calendar),
          systemImage: "clock"
        ),
        HistoryReportMetric(
          title: HistoryCopy.wakeTime,
          value: wakeText,
          systemImage: "sun.haze"
        ),
      ]
    )
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

struct HistoryRecordCard: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let result: HistoryStepResult

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: MoruPilotSpacing.eight) {
        ZStack {
          Circle()
            .stroke(
              Color(red: 117 / 255, green: 161 / 255, blue: 1),
              lineWidth: 1
            )
            .frame(width: 18, height: 18)

          Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(
              Color(red: 117 / 255, green: 161 / 255, blue: 1)
            )
        }
        .accessibilityHidden(true)

        Text(result.stepTitle)
          .historyOverviewTextStyle(.b4.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textStrong)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: MoruPilotSpacing.eight)

        Text(result.displayText)
          .historyOverviewTextStyle(.c1)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(MoruPilotSpacing.twenty)

      Text(recordText)
        .historyOverviewTextStyle(.b4)
        .foregroundStyle(MoruPilotColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MoruPilotSpacing.twenty)
        .background(AppColor.grayWhite.opacity(0.2))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(historyPilotSurface)
    .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard))
    .shadow(color: MoruPilotColor.shadow, radius: 7.5, x: 0, y: 0)
    .accessibilityElement(children: .combine)
  }

  private var recordText: String {
    if let transcript = result.transcript, !transcript.isEmpty {
      return transcript
    }

    return HistoryCopy.noTranscripts
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

private struct HistoryDetailSectionTitle: View {
  let title: String

  var body: some View {
    Text(title)
      .historyOverviewTextStyle(.b3.weight(.semiBold))
      .foregroundStyle(MoruPilotColor.textPrimary)
      .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityAddTraits(.isHeader)
  }
}

private struct HistoryDetailHeader: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let title: String

  var body: some View {
    HStack {
      Button {
        dismiss()
      } label: {
        if dynamicTypeSize.isAccessibilitySize {
          Image(systemName: "chevron.backward")
            .font(.system(size: 20, weight: .semibold))
        } else {
          Text("뒤로")
            .historyOverviewTextStyle(.b4)
        }
      }
      .foregroundStyle(MoruPilotColor.textTertiary)
      .frame(minWidth: 44, minHeight: 44, alignment: .leading)
      .accessibilityLabel("뒤로")
      .accessibilityHint("이전 화면으로 돌아갑니다.")

      Spacer()

      Color.clear
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
    .overlay {
      Text(title)
        .historyOverviewTextStyle(.h3)
        .foregroundStyle(MoruPilotColor.textStrong)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityAddTraits(.isHeader)
    }
    .padding(.horizontal, MoruPilotSpacing.twenty)
    .frame(height: 54)
  }
}

struct HistoryDailyDetailView: View {
  let day: HistoryDaySummary
  let calendar: Calendar

  var body: some View {
    VStack(spacing: 0) {
      HistoryDetailHeader(title: HistoryCopy.dailyReportTitle)

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: MoruPilotSpacing.thirtyTwo) {
          HistoryDailySummaryCard(day: day, calendar: calendar)

          VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
            HistoryDetailSectionTitle(title: HistoryCopy.todayRecords)

            if day.recordedStepResults.isEmpty {
              HistoryInlineEmptyCard(message: HistoryCopy.noTranscripts)
            } else {
              VStack(spacing: MoruPilotSpacing.twelve) {
                ForEach(day.recordedStepResults, id: \.stepID) { result in
                  HistoryRecordCard(result: result)
                }
              }
            }
          }

          VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
            HistoryDetailSectionTitle(title: HistoryCopy.itemResults)

            if day.stepResults.isEmpty {
              HistoryInlineEmptyCard(message: HistoryCopy.noStepResults)
            } else {
              LazyVStack(spacing: MoruPilotSpacing.twelve) {
                ForEach(
                  Array(day.stepResults.enumerated()),
                  id: \.element.stepID
                ) { index, result in
                  HistoryStepResultRow(
                    index: index + 1,
                    title: result.stepTitle,
                    resultText: result.displayText,
                    isCompleted: result.isCompleted,
                    transcript: nil
                  )
                }
              }
            }
          }
        }
        .padding(.horizontal, MoruPilotSpacing.twenty)
        .padding(.top, MoruPilotSpacing.eight)
        .padding(.bottom, MoruPilotSpacing.sixtyFour)
      }
    }
    .background(MoruPilotColor.canvas.ignoresSafeArea())
    .toolbar(.hidden, for: .navigationBar)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("history.dailyDetail")
  }
}

struct HistoryRunDetailView: View {
  let run: HistoryRun
  let calendar: Calendar

  var body: some View {
    VStack(spacing: 0) {
      HistoryDetailHeader(title: dateTitle)

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: MoruPilotSpacing.thirtyTwo) {
          HistoryReportSummaryCard(
            metrics: [
              HistoryReportMetric(
                title: HistoryCopy.completionRate,
                value: "\(Int((run.completionRate * 100).rounded()))%",
                systemImage: "checkmark"
              ),
              HistoryReportMetric(
                title: HistoryCopy.duration,
                value: run.elapsedText,
                systemImage: "clock"
              ),
              HistoryReportMetric(
                title: HistoryCopy.wakeTime,
                value: wakeText,
                systemImage: "sun.haze"
              ),
            ]
          )

          VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
            HistoryDetailSectionTitle(title: HistoryCopy.todayRecords)

            if run.recordedStepResults.isEmpty {
              HistoryInlineEmptyCard(message: HistoryCopy.noTranscripts)
            } else {
              VStack(spacing: MoruPilotSpacing.twelve) {
                ForEach(run.recordedStepResults, id: \.stepID) { result in
                  HistoryRecordCard(result: result)
                }
              }
            }
          }

          VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
            HistoryDetailSectionTitle(title: HistoryCopy.itemResults)

            if run.stepResults.isEmpty {
              HistoryInlineEmptyCard(message: HistoryCopy.noStepResults)
            } else {
              LazyVStack(spacing: MoruPilotSpacing.twelve) {
                ForEach(
                  Array(run.stepResults.enumerated()),
                  id: \.element.stepID
                ) { index, result in
                  HistoryStepResultRow(
                    index: index + 1,
                    title: result.stepTitle,
                    resultText: result.displayText,
                    isCompleted: result.isCompleted,
                    transcript: nil
                  )
                }
              }
            }
          }
        }
        .padding(.horizontal, MoruPilotSpacing.twenty)
        .padding(.top, MoruPilotSpacing.eight)
        .padding(.bottom, MoruPilotSpacing.sixtyFour)
      }
    }
    .background(MoruPilotColor.canvas.ignoresSafeArea())
    .toolbar(.hidden, for: .navigationBar)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("history.runDetail")
  }

  private var dateTitle: String {
    historyFormattedDate(
      run.startedAt,
      calendar: calendar,
      format: .dateTime.month().day().weekday(.wide)
    )
  }

  private var wakeText: String {
    historyFormattedDate(
      run.startedAt,
      calendar: calendar,
      format: Date.FormatStyle(date: .omitted, time: .shortened)
    )
  }
}

struct HistoryDestinationMissingView: View {
  let retryAction: () -> Void
  let backAction: () -> Void

  var body: some View {
    HistoryStatusView(
      systemImage: "exclamationmark.triangle.fill",
      title: HistoryCopy.missingRunTitle,
      message: HistoryCopy.missingRunMessage,
      primaryActionTitle: HistoryCopy.retry,
      primaryAction: retryAction,
      secondaryActionTitle: HistoryCopy.returnToHistory,
      secondaryAction: backAction
    )
    .accessibilityIdentifier("history.runDetail.missing")
  }
}


struct HistoryWeeklyReportView: View {
  let overview: HistoryOverview
  @State private var selectedDay: HistoryDaySummary?

  private var report: HistoryWeekReport {
    overview.week
  }

  private var calendar: Calendar {
    overview.calendar
  }

  var body: some View {
    VStack(spacing: 0) {
      HistoryDetailHeader(title: HistoryCopy.weeklyReportTitle)

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: MoruPilotSpacing.thirtyTwo) {
          HistoryWeeklySummaryCard(
            title: weekRangeText,
            completedRuns: report.completedRunCount,
            totalRuns: report.totalRunCount,
            completionRate: report.completionRate,
            completionRateChangePercentagePoints:
              report.completionRateChangePercentagePoints,
            averageDurationText: overview.weeklyAverageElapsedText
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
        .padding(.horizontal, MoruPilotSpacing.twenty)
        .padding(.top, MoruPilotSpacing.eight)
        .padding(.bottom, MoruPilotSpacing.sixtyFour)
      }
    }
    .background(MoruPilotColor.canvas.ignoresSafeArea())
    .toolbar(.hidden, for: .navigationBar)
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
