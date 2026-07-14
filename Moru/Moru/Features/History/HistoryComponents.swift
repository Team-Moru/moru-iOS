//
//  HistoryComponents.swift
//  Moru
//
//  Created by Codex on 7/14/26.
//

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
    .accessibilityLabel("이번 주 루틴 리포트, 완료율 \(Int((completionRate * 100).rounded()))퍼센트")
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

      Text("기록을 불러오지 못했어요.")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Text(message)
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
        .multilineTextAlignment(.center)

      MoruButton("다시 시도", style: .secondary, action: retryAction)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(AppSpacing.xxl)
  }
}
