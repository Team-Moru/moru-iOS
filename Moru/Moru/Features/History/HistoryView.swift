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
    destination: Binding<HistoryDestination?>,
    in overview: HistoryOverview
  ) -> HistoryRunDetailDestinationResolution {
    guard let pendingDestination = destination.wrappedValue else {
      return .noPendingDestination
    }

    switch pendingDestination {
    case .runDetail(let runID):
      let matchingRuns = overview.recentDays
        .flatMap(\.runs)
        .filter { $0.id == runID }

      guard matchingRuns.count == 1, let run = matchingRuns.first else {
        return .missing
      }

      destination.wrappedValue = nil
      return .selected(
        HistoryRunDetailDestinationPresentation(run: run, calendar: overview.calendar)
      )
    }
  }
}
struct HistoryView: View {
  @State private var viewModel: HistoryViewModel
  @State private var isWeeklyReportPresented = false
  @Binding private var pendingDestination: HistoryDestination?
  @State private var selectedRun: HistoryRun?
  @State private var selectedRunCalendar: Calendar?
  @State private var isDestinationMissingScreenPresented = false

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
          overviewContent(overview)
            .onAppear {
              resolvePendingDestination(in: overview)
            }
        case .empty:
          HistoryEmptyView(
            title: "아직 기록이 없어요.",
            message: "루틴을 완료하면 이곳에서 매일의 기록과 주간 리포트를 확인할 수 있어요."
          )
          .onAppear {
            presentMissingDestination()
          }
        case .failed(let message):
          HistoryFailureView(
            message: message,
            retryAction: viewModel.retryButtonDidTap
          )
        }
      }
      .background(AppColor.babyBlue50.ignoresSafeArea())
      .navigationTitle("기록")
      .navigationBarTitleDisplayMode(.large)
      .navigationDestination(isPresented: $isWeeklyReportPresented) {
        if case .content(let overview) = viewModel.state {
          HistoryWeeklyReportView(report: overview.week, calendar: overview.calendar)
        }
      }
      .navigationDestination(isPresented: isRunDetailPresented) {
        if let selectedRun, let selectedRunCalendar {
          HistoryRunDetailView(run: selectedRun, calendar: selectedRunCalendar)
        } else {
          EmptyView()
        }
      }
      .navigationDestination(isPresented: isDestinationMissingPresented) {
        HistoryDestinationMissingView(
          retryAction: retryPendingDestination,
          backAction: dismissMissingDestination
        )
      }
    }
    .task {
      viewModel.load()
    }
    .onChange(of: pendingDestination) { _, destination in
      guard destination != nil,
            case .content(let overview) = viewModel.state else {
        return
      }

      resolvePendingDestination(in: overview)
    }
  }

  private func overviewContent(_ overview: HistoryOverview) -> some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: AppSpacing.xl) {
        HistoryWeeklySummaryCard(
          title: historyWeekRangeText(
            from: overview.week.weekStartDate,
            toExclusive: overview.week.weekEndDate,
            calendar: overview.calendar
          ),
          completedRuns: overview.week.completedRunCount,
          totalRuns: overview.week.totalRunCount,
          completionRate: overview.week.completionRate,
          action: {
            isWeeklyReportPresented = true
          }
        )

        HistoryWakeMetricsView(metrics: overview.wakeMetrics)
        HistoryMonthlyHeatmapView(
          heatmap: overview.monthlyHeatmap,
          calendar: overview.calendar
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
      .padding(.top, AppSpacing.lg)
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
  private var isDestinationMissingPresented: Binding<Bool> {
    Binding(
      get: { isDestinationMissingScreenPresented },
      set: { isPresented in
        guard !isPresented else {
          return
        }

        pendingDestination = nil
        isDestinationMissingScreenPresented = false
      }
    )
  }

  private func resolvePendingDestination(in overview: HistoryOverview) {
    switch HistoryRunDetailDestinationResolver.resolve(
      destination: $pendingDestination,
      in: overview
    ) {
    case .noPendingDestination:
      return
    case .selected(let presentation):
      selectedRun = presentation.run
      selectedRunCalendar = presentation.calendar
      isDestinationMissingScreenPresented = false
    case .missing:
      presentMissingDestination()
    }
  }

  private func retryPendingDestination() {
    viewModel.load()

    switch viewModel.state {
    case .content(let overview):
      resolvePendingDestination(in: overview)
    case .empty:
      presentMissingDestination()
    case .loading, .failed:
      break
    }
  }

  private func presentMissingDestination() {
    guard pendingDestination != nil, selectedRun == nil else {
      return
    }

    isDestinationMissingScreenPresented = true
  }

  private func dismissMissingDestination() {
    pendingDestination = nil
    isDestinationMissingScreenPresented = false
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

private struct HistoryDaySummaryRow: View {
  let day: HistoryDaySummary
  let calendar: Calendar
  var body: some View {
    HStack(spacing: AppSpacing.sm) {
      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text(historyFormattedDate(
          day.date,
          calendar: calendar,
          format: .dateTime.month(.wide).day().weekday(.abbreviated)
        ))
          .font(AppFont.label1NormalSemiBold)
          .foregroundStyle(AppColor.moruTextPrimary)

        Text("\(day.totalRunCount)회 실행")
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)
      }

      Spacer()

      VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
        Text("\(Int((day.completionRate * 100).rounded()))% 완료")
          .font(AppFont.caption1SemiBold)
          .foregroundStyle(AppColor.orange500)

        Text("\(day.completedRunCount)/\(day.totalRunCount) 완료")
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)
      }

      Image(systemName: "chevron.right")
        .font(AppFont.caption1SemiBold)
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .padding(AppSpacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppColor.grayWhite)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    .overlay {
      RoundedRectangle(cornerRadius: AppRadius.md)
        .stroke(AppColor.moruBorder, lineWidth: 1)
    }
  }
}

private struct HistoryDailyDetailView: View {
  let day: HistoryDaySummary
  let calendar: Calendar
  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: AppSpacing.xl) {
        MoruCard(backgroundColor: AppColor.grayWhite) {
          Text("하루 요약")
            .font(AppFont.heading3SemiBold)
            .foregroundStyle(AppColor.moruTextPrimary)

          HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
            Text("\(Int((day.completionRate * 100).rounded()))%")
              .font(AppFont.title3Bold)
              .foregroundStyle(AppColor.orange500)

            Text("완료율")
              .font(AppFont.caption1Medium)
              .foregroundStyle(AppColor.moruTextSecondary)
          }

          VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("\(day.completedRunCount)/\(day.totalRunCount)회 완료")
              .font(AppFont.caption1Medium)
              .foregroundStyle(AppColor.moruTextSecondary)

            HistoryCompletionRateBar(completionRate: day.completionRate)
          }
        }

        HistorySectionHeader(title: "실행 기록", actionTitle: nil, action: nil)

        LazyVStack(spacing: AppSpacing.lg) {
          ForEach(day.runs, id: \.id) { run in
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
        }
      }
      .padding(.horizontal, AppSpacing.screenHorizontal)
      .padding(.top, AppSpacing.lg)
      .padding(.bottom, AppSpacing.xxl)
    }
    .background(AppColor.babyBlue50.ignoresSafeArea())
    .navigationTitle(historyFormattedDate(
      day.date,
      calendar: calendar,
      format: .dateTime.month(.wide).day()
    ))
    .navigationBarTitleDisplayMode(.inline)
  }
}
private struct HistoryRunDetailView: View {
  let run: HistoryRun
  let calendar: Calendar

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: AppSpacing.xl) {
        MoruCard(backgroundColor: AppColor.grayWhite) {
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
    .background(AppColor.babyBlue50.ignoresSafeArea())
    .navigationTitle("실행 기록")
    .navigationBarTitleDisplayMode(.inline)
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
      MoruButton("뒤로 가기", style: .text, action: backAction)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(AppSpacing.xxl)
    .navigationTitle("실행 기록")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("history.runDetail.missing")
  }
}


private struct HistoryWeeklyReportView: View {
  let report: HistoryWeekReport
  let calendar: Calendar
  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: AppSpacing.xl) {
        MoruCard(backgroundColor: AppColor.grayWhite) {
          Text("이번 주 요약")
            .font(AppFont.heading3SemiBold)
            .foregroundStyle(AppColor.moruTextPrimary)

          HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
            Text("\(Int((report.completionRate * 100).rounded()))%")
              .font(AppFont.title3Bold)
              .foregroundStyle(AppColor.orange500)

            Text("완료율")
              .font(AppFont.caption1Medium)
              .foregroundStyle(AppColor.moruTextSecondary)
          }

          VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("\(report.completedRunCount)/\(report.totalRunCount)회 완료")
              .font(AppFont.caption1Medium)
              .foregroundStyle(AppColor.moruTextSecondary)

            HistoryCompletionRateBar(completionRate: report.completionRate)
          }
        }

        HistorySectionHeader(title: "요일별 완료율", actionTitle: nil, action: nil)

        LazyVStack(spacing: AppSpacing.sm) {
          ForEach(report.dailyCompletionRates, id: \.date) { completion in
            HistoryWeeklyDailyRateRow(completion: completion, calendar: calendar)
          }
        }
      }
      .padding(.horizontal, AppSpacing.screenHorizontal)
      .padding(.top, AppSpacing.lg)
      .padding(.bottom, AppSpacing.xxl)
    }
    .background(AppColor.babyBlue50.ignoresSafeArea())
    .navigationTitle(weekRangeText)
    .navigationBarTitleDisplayMode(.inline)
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
