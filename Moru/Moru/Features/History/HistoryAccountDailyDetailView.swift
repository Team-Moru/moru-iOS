//
//  HistoryAccountDailyDetailView.swift
//  Moru
//

import Foundation
import SwiftUI

struct HistoryAccountDailyDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var viewModel: HistoryAccountDailyViewModel

  init(viewModel: HistoryAccountDailyViewModel) {
    _viewModel = State(initialValue: viewModel)
  }

  var body: some View {
    VStack(spacing: 0) {
      header

      Group {
        switch viewModel.state {
        case .loading:
          HistoryStatusView(
            systemImage: "icloud.and.arrow.down",
            title: HistoryCopy.accountDailyLoading,
            message: HistoryCopy.accountDailyLoadingMessage
          )
          .accessibilityAddTraits(.updatesFrequently)
        case .content(let report):
          content(report)
        case .failed(let message):
          HistoryFailureView(
            message: message,
            retryAction: {
              Task {
                await viewModel.retryButtonDidTap()
              }
            }
          )
        }
      }
    }
    .background(MoruPilotColor.canvas.ignoresSafeArea())
    .toolbar(.hidden, for: .navigationBar)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("history.accountDailyDetail")
    .task {
      await viewModel.load()
    }
  }

  private var header: some View {
    HStack {
      Button {
        dismiss()
      } label: {
        Text("뒤로")
          .historyOverviewTextStyle(.b4)
      }
      .foregroundStyle(MoruPilotColor.textTertiary)
      .frame(minWidth: 44, minHeight: 44, alignment: .leading)
      .accessibilityLabel("뒤로")

      Spacer()

      Color.clear
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
    .overlay {
      Text(dateTitle)
        .historyOverviewTextStyle(.h3)
        .foregroundStyle(MoruPilotColor.textStrong)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityAddTraits(.isHeader)
        .allowsHitTesting(false)
    }
    .padding(.horizontal, MoruPilotSpacing.twenty)
    .frame(height: 54)
  }

  private func content(
    _ report: ServerHistoryDailySummary
  ) -> some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: MoruPilotSpacing.thirtyTwo) {
        HistoryReportSummaryCard(
          metrics: [
            HistoryReportMetric(
              title: HistoryCopy.completionRate,
              value: "\(Int((report.completionRate * 100).rounded()))%",
              systemImage: "checkmark"
            ),
            HistoryReportMetric(
              title: HistoryCopy.duration,
              value: durationText(report.totalDurationSeconds),
              systemImage: "clock"
            ),
            HistoryReportMetric(
              title: HistoryCopy.wakeTime,
              value: minuteText(report.actualWakeMinute),
              systemImage: "sun.haze"
            ),
          ]
        )

        Label {
          Text(
            "\(HistoryCopy.accountRecordNotice) · "
              + "현재 연속 \(report.currentStreak)일"
          )
          .historyOverviewTextStyle(.c1)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "icloud")
            .foregroundStyle(MoruPilotColor.accent)
            .accessibilityHidden(true)
        }
        .padding(MoruPilotSpacing.sixteen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.grayWhite.opacity(0.72))
        .clipShape(
          RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard)
        )

        VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
          accountSectionTitle(HistoryCopy.todayRecords)

          let records = report.routines.filter {
            DailyReportInputAnswerPolicy.answer(for: $0) != nil
          }
          if records.isEmpty {
            HistoryInlineEmptyCard(message: HistoryCopy.noTranscripts)
          } else {
            VStack(spacing: MoruPilotSpacing.twelve) {
              ForEach(
                Array(records.enumerated()),
                id: \.offset
              ) { _, routine in
                accountRecordCard(routine)
              }
            }
          }
        }

        VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
          accountSectionTitle(HistoryCopy.itemResults)

          if report.routines.isEmpty {
            HistoryInlineEmptyCard(message: HistoryCopy.noStepResults)
          } else {
            LazyVStack(spacing: MoruPilotSpacing.twelve) {
              ForEach(
                Array(report.routines.enumerated()),
                id: \.offset
              ) { index, routine in
                HistoryStepResultRow(
                  index: index + 1,
                  title: routine.title,
                  resultText: accountResultText(routine),
                  isCompleted: routine.isCompleted
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

  private func accountSectionTitle(_ title: String) -> some View {
    Text(title)
      .historyOverviewTextStyle(.b3.weight(.semiBold))
      .foregroundStyle(MoruPilotColor.textPrimary)
      .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityAddTraits(.isHeader)
  }

  private func accountRecordCard(
    _ routine: ServerHistoryDailyRoutine
  ) -> some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      Text(routine.title)
        .historyOverviewTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)

      Text(
        DailyReportInputAnswerPolicy.answer(for: routine)
          ?? HistoryCopy.noTranscripts
      )
        .historyOverviewTextStyle(.b4)
        .foregroundStyle(MoruPilotColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(MoruPilotSpacing.twenty)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(historyPilotSurface)
    .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard))
    .accessibilityElement(children: .combine)
  }

  private func accountResultText(
    _ routine: ServerHistoryDailyRoutine
  ) -> String {
    let result = routine.isCompleted ? "완료" : "미완료"
    return "\(result) · \(routine.type.displayText) · "
      + durationText(routine.durationSeconds)
  }

  private var dateTitle: String {
    var format = Date.FormatStyle()
      .month()
      .day()
      .weekday(.wide)
    format.calendar = viewModel.calendar
    format.timeZone = viewModel.calendar.timeZone
    format.locale = viewModel.calendar.locale ?? .autoupdatingCurrent
    return viewModel.date.formatted(format)
  }

  private func durationText(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }

  private func minuteText(_ minute: Int?) -> String {
    guard let minute else {
      return "--:--"
    }
    return String(format: "%02d:%02d", minute / 60, minute % 60)
  }
}

private extension ServerHistoryDailyRoutineType {
  var displayText: String {
    switch self {
    case .check:
      "확인"
    case .timer:
      "타이머"
    case .input:
      "입력"
    }
  }
}
