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
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Spacer()

      if let actionTitle, let action {
        Button(action: action) {
          HStack(spacing: AppSpacing.xxs) {
            Text(actionTitle)
            Image(systemName: "chevron.right")
          }
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)
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
      MoruCard(backgroundColor: AppColor.grayWhite) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
              .font(AppFont.label1NormalMedium)
              .foregroundStyle(AppColor.moruTextSecondary)

            Text("이번 주 루틴 리포트")
              .font(AppFont.heading3SemiBold)
              .foregroundStyle(AppColor.moruTextPrimary)
          }

          Spacer()

          Image(systemName: "chevron.right")
            .font(AppFont.caption1SemiBold)
            .foregroundStyle(AppColor.moruTextSecondary)
            .padding(.top, AppSpacing.xxs)
        }

        VStack(alignment: .leading, spacing: AppSpacing.xs) {
          HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
            Text("\(Int((completionRate * 100).rounded()))%")
              .font(AppFont.title3Bold)
              .foregroundStyle(AppColor.orange500)

            Text("완료율")
              .font(AppFont.caption1Medium)
              .foregroundStyle(AppColor.moruTextSecondary)
          }

          VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("\(completedRuns)/\(totalRuns)회 완료")
              .font(AppFont.caption1Medium)
              .foregroundStyle(AppColor.moruTextSecondary)

            HistoryCompletionRateBar(completionRate: completionRate)
          }
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      "\(title), 이번 주 루틴 리포트, \(completedRuns)/\(totalRuns)회 완료, "
        + "완료율 \(Int((completionRate * 100).rounded()))퍼센트"
    )
  }
}
struct HistoryWakeMetricsView: View {
  let metrics: HistoryWakeMetrics

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.md) {
      HistorySectionHeader(title: "기상 기록", actionTitle: nil, action: nil)

      if metrics == .unavailable {
        HistoryMetricCard(
          title: "평균 기상 시간",
          value: "확인할 수 없어요",
          detail: nil
        )
        .accessibilityIdentifier("history.metrics.averageWake")

        Text("알람 기상 기록을 확인할 수 없어요")
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)
      } else {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
          HistoryMetricCard(
            title: "평균 기상 시간",
            value: averageWakeText,
            detail: nil
          )
          .accessibilityIdentifier("history.metrics.averageWake")

          HistoryMetricCard(
            title: "시작 시간 규칙성",
            value: regularityText,
            detail: deviationText
          )
        }

        Text("최근 28일 중 \(metrics.observationCount)회 관측 기준")
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)
      }
    }
  }

  private var averageWakeText: String {
    guard metrics.observationCount >= 3, let minute = metrics.averageWakeMinute else {
      return "기록이 더 필요해요"
    }

    return String(format: "%02d:%02d", minute / 60, minute % 60)
  }

  private var regularityText: String {
    guard metrics.observationCount >= 3, let score = metrics.consistencyScore else {
      return "기록이 더 필요해요"
    }

    switch score {
    case 90...:
      return "매우 일정해요"
    case 75..<90:
      return "규칙적이에요"
    case 50..<75:
      return "조금 들쑥날쑥해요"
    default:
      return "기상 시간이 많이 달라요"
    }
  }

  private var deviationText: String? {
    guard metrics.observationCount >= 3, let minutes = metrics.averageDeviationMinutes else {
      return nil
    }

    return "평균에서 \(minutes)분 차이"
  }
}

private struct HistoryMetricCard: View {
  let title: String
  let value: String
  let detail: String?

  var body: some View {
    MoruCard(backgroundColor: AppColor.grayWhite) {
      Text(title)
        .font(AppFont.label1NormalSemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Text(value)
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.orange500)
        .lineLimit(2)
        .minimumScaleFactor(0.8)

      if let detail {
        Text(detail)
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
      dateText = date.formatted(.dateTime.year().month(.wide).day())
    }

    if let completionRate = day.completionRate {
      accessibilityLabel = "\(dateText), 완료율 \(Int((completionRate * 100).rounded()))퍼센트"
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
    VStack(alignment: .leading, spacing: AppSpacing.md) {
      HistorySectionHeader(title: "이번 달 루틴 완료", actionTitle: nil, action: nil)

      MoruCard(backgroundColor: AppColor.grayWhite) {
        LazyVGrid(columns: columns, spacing: AppSpacing.xxs) {
          ForEach(["월", "화", "수", "목", "금", "토", "일"], id: \.self) { weekday in
            Text(weekday)
              .font(AppFont.caption1Medium)
              .foregroundStyle(AppColor.moruTextSecondary)
              .frame(maxWidth: .infinity)
          }

          ForEach(heatmap.days) { day in
            let presentation = HistoryHeatmapCellPresentation(day: day, calendar: calendar)

            RoundedRectangle(cornerRadius: AppRadius.xs)
              .fill(fillColor(for: day.bucket))
              .frame(height: 24)
              .accessibilityLabel(presentation.accessibilityLabel ?? "")
              .accessibilityHidden(presentation.isAccessibilityHidden)
          }
        }

        Text("색상 안내: 회색은 기록 없음 또는 0%, 파랑은 1–49%, 주황은 50–100% 완료")
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)
      }
    }
    .accessibilityIdentifier("history.heatmap")
  }

  private func fillColor(for bucket: HistoryHeatmapBucket) -> Color {
    switch bucket {
    case .noData:
      AppColor.gray100
    case .zero:
      AppColor.gray200
    case .low:
      AppColor.babyBlue150
    case .medium:
      AppColor.babyBlue250
    case .high:
      AppColor.orange200
    case .complete:
      AppColor.orange400
    }
  }
}

struct HistoryCompletionRateBar: View {
  let completionRate: Double

  private var clampedCompletionRate: Double {
    min(max(completionRate, 0), 1)
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(AppColor.moruSurfaceMuted)

        Capsule()
          .fill(AppColor.orange350)
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
      Image(systemName: isCompleted ? "checkmark.circle.fill" : "xmark.circle.fill")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(isCompleted ? AppColor.orange400 : AppColor.gray350)

      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text(routineName)
          .font(AppFont.label1NormalSemiBold)
          .foregroundStyle(AppColor.moruTextPrimary)
          .lineLimit(1)

        Text(timeText)
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)
      }

      Spacer()

      Text(completionText)
        .font(AppFont.caption1SemiBold)
        .foregroundStyle(isCompleted ? AppColor.orange500 : AppColor.moruTextSecondary)
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
            .fill(isCompleted ? AppColor.orange300 : AppColor.gray250)
            .frame(width: 24, height: 24)

          Text("\(index)")
            .font(AppFont.caption1SemiBold)
            .foregroundStyle(AppColor.grayWhite)
        }

        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
          Text(title)
            .font(AppFont.label1NormalSemiBold)
            .foregroundStyle(AppColor.moruTextPrimary)

          Text(resultText)
            .font(AppFont.caption1Medium)
            .foregroundStyle(AppColor.moruTextSecondary)
        }

        Spacer()

        Image(systemName: isCompleted ? "checkmark.circle.fill" : "minus.circle.fill")
          .font(AppFont.body1NormalMedium)
          .foregroundStyle(isCompleted ? AppColor.orange400 : AppColor.gray350)
      }

      if let transcript, !transcript.isEmpty {
        Text(transcript)
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextBody)
          .padding(AppSpacing.sm)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(AppColor.moruSurfaceMuted)
          .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
          .accessibilityLabel("음성 기록: \(transcript)")
      }
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

struct HistoryLoadingView: View {
  var body: some View {
    VStack(spacing: AppSpacing.sm) {
      ProgressView()
        .tint(AppColor.orange400)
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
        .foregroundStyle(AppColor.orange300)

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
        .foregroundStyle(AppColor.orange500)

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
