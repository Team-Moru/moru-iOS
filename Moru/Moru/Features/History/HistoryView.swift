//
//  HistoryView.swift
//  Moru
//
//  Created by Codex on 7/14/26.
//

import Foundation
import SwiftUI

struct HistoryView: View {
  @State private var viewModel: HistoryViewModel
  @State private var isWeeklyReportPresented = false

  init(viewModel: HistoryViewModel) {
    _viewModel = State(initialValue: viewModel)
  }

  var body: some View {
    NavigationStack {
      Group {
        switch viewModel.state {
        case .loading:
          HistoryLoadingView()
        case .content(let overview):
          overviewContent(overview)
        case .empty:
          HistoryEmptyView(
            title: "아직 기록이 없어요.",
            message: "루틴을 완료하면 이곳에서 매일의 기록과 주간 리포트를 확인할 수 있어요."
          )
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
          HistoryWeeklyReportView(report: overview.week)
        }
      }
    }
    .task {
      viewModel.load()
    }
  }

  private func overviewContent(_ overview: HistoryOverview) -> some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: AppSpacing.xl) {
        HistoryWeeklySummaryCard(
          title: weekRangeText(
            from: overview.week.weekStartDate,
            toExclusive: overview.week.weekEndDate
          ),
          completedRuns: overview.week.completedRunCount,
          totalRuns: overview.week.totalRunCount,
          completionRate: overview.week.completionRate,
          action: {
            isWeeklyReportPresented = true
          }
        )

        HistorySectionHeader(title: "최근 기록", actionTitle: nil, action: nil)

        LazyVStack(spacing: AppSpacing.sm) {
          ForEach(overview.recentDays, id: \.date) { day in
            NavigationLink {
              HistoryDailyDetailView(day: day)
            } label: {
              HistoryDaySummaryRow(day: day)
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

  private func weekRangeText(from startDate: Date, toExclusive endDate: Date) -> String {
    let finalDate = Calendar.current.date(byAdding: .day, value: -1, to: endDate) ?? endDate
    return "\(startDate.formatted(.dateTime.month(.wide).day())) ~ "
      + finalDate.formatted(.dateTime.month(.wide).day())
  }
}

private struct HistoryDaySummaryRow: View {
  let day: HistoryDaySummary

  var body: some View {
    HStack(spacing: AppSpacing.sm) {
      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text(day.date.formatted(.dateTime.month(.wide).day().weekday(.abbreviated)))
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
                timeText: run.startedAt.formatted(date: .omitted, time: .shortened),
                completionText: statusText(for: run.status),
                isCompleted: run.status == .completed
              )

              ForEach(Array(run.stepResults.enumerated()), id: \.element.stepID) { index, result in
                HistoryStepResultRow(
                  index: index + 1,
                  title: result.stepTitle,
                  resultText: stepResultText(for: result),
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
    .navigationTitle(day.date.formatted(.dateTime.month(.wide).day()))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func statusText(for status: HistoryRunStatus) -> String {
    switch status {
    case .completed:
      return "완료"
    case .partial:
      return "일부 완료"
    case .endedEarly:
      return "중단됨"
    }
  }

  private func stepResultText(for result: HistoryStepResult) -> String {
    if result.isCompleted {
      return "완료"
    }

    return result.isSkipped ? "건너뜀" : "미완료"
  }
}

private struct HistoryWeeklyReportView: View {
  let report: HistoryWeekReport

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
            HistoryWeeklyDailyRateRow(completion: completion)
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
    let finalDate = Calendar.current.date(
      byAdding: .day,
      value: -1,
      to: report.weekEndDate
    ) ?? report.weekEndDate

    return "\(report.weekStartDate.formatted(.dateTime.month(.wide).day())) ~ "
      + finalDate.formatted(.dateTime.month(.wide).day())
  }
}

private struct HistoryWeeklyDailyRateRow: View {
  let completion: HistoryDailyCompletion

  var body: some View {
    HStack(spacing: AppSpacing.md) {
      Text(completion.date.formatted(.dateTime.weekday(.abbreviated)))
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
