//
//  TodayRoutineProgressCard.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct TodayRoutineProgressCard: View {
  private enum Metric {
    static let percentAlignmentOffset: CGFloat = -5
  }

  let progress: HomeProgressState
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(spacing: MoruPilotSpacing.eight) {
      ZStack {
        Circle()
          .stroke(MoruPilotColor.progressTrack, lineWidth: ringLineWidth)
          .frame(width: progressRingSize, height: progressRingSize)

        Circle()
          .trim(from: 0, to: min(max(progress.progress, 0), 1))
          .stroke(
            progressGradient,
            style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
          )
          .rotationEffect(.degrees(-90))
          .frame(width: progressRingSize, height: progressRingSize)

        VStack(spacing: 0) {
          HStack(spacing: 0) {
            Text(percentSymbolText)
              .hidden()
            Text(percentValueText)
            Text(percentSymbolText)
          }
            .homeFigmaTextStyle(.h2)
            .foregroundStyle(MoruPilotColor.textPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .offset(x: Metric.percentAlignmentOffset)

          Text(progress.completedText)
            .homeFigmaTextStyle(.c2.weight(.regular))
            .foregroundStyle(MoruPilotColor.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(width: progressRingSize, alignment: .center)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(HomeCopy.todayRoutine)
      .accessibilityValue("\(progress.percentText), \(progress.completedText)")

      Text(HomeCopy.todayRoutine)
        .homeFigmaTextStyle(.c1.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textSecondary)
    }
    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 20 : 22)
    .padding(.horizontal, MoruPilotSpacing.sixteen)
    .frame(maxWidth: .infinity)
    .frame(minHeight: cardMinimumHeight)
    .homePilotSurface()
  }

  private var progressRingSize: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 164 : 112
  }

  private var cardMinimumHeight: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 272 : 184
  }

  private var ringLineWidth: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 10 : 8
  }

  private var percentValueText: String {
    progress.percentText.hasSuffix("%")
      ? String(progress.percentText.dropLast())
      : progress.percentText
  }

  private var percentSymbolText: String {
    progress.percentText.hasSuffix("%") ? "%" : ""
  }

  private var progressGradient: LinearGradient {
    LinearGradient(
      stops: [
        Gradient.Stop(color: AppColor.orange350.opacity(0.3), location: 0),
        Gradient.Stop(color: AppColor.orange350, location: 1),
      ],
      startPoint: UnitPoint(x: 0.95, y: 0.34),
      endPoint: UnitPoint(x: 0.05, y: 0.66)
    )
  }
}

#Preview {
  TodayRoutineProgressCard(progress: .placeholder)
    .padding()
    .background(AppColor.babyBlue50)
}
