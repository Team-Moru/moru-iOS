//
//  RoutineFinishedView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import SwiftUI

struct RoutineFinishedView: View {
  /// 0.0~1.0 범위
  let completionRate: Double

  /// 저장된 일반 실행에서 다시 계산한 연속 달성 기록.
  /// 체험에는 값이 없다.
  let streak: RoutineStreak?

  /// 실제 완료한 루틴 단계 제목
  let completedStepTitles: [String]

  /// 저장하지 않는 온보딩 체험 완료 상태
  let isTrial: Bool

  /// 오늘의 기록 화면으로 이동
  let onTapTodayRecord: () -> Void

  /// 완료 화면을 닫고 상위 flow로 이동
  let onTapHome: () -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var animatedProgress: Double

  init(
    completionRate: Double,
    streak: RoutineStreak?,
    completedStepTitles: [String],
    isTrial: Bool = false,
    onTapTodayRecord: @escaping () -> Void,
    onTapHome: @escaping () -> Void
  ) {
    self.completionRate = completionRate
    self.streak = streak
    self.completedStepTitles = completedStepTitles
    self.isTrial = isTrial
    self.onTapTodayRecord = onTapTodayRecord
    self.onTapHome = onTapHome
    _animatedProgress = State(
      initialValue: min(max(completionRate, 0), 1)
    )
  }

  private var normalizedCompletionRate: Double {
    min(max(completionRate, 0), 1)
  }

  private var completionPercentage: Int {
    Int((normalizedCompletionRate * 100).rounded())
  }

  private var topContentPadding: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 24 : 188
  }

  private var stepColumns: [GridItem] {
    if dynamicTypeSize.isAccessibilitySize {
      return [GridItem(.flexible(), alignment: .leading)]
    }

    return [
      GridItem(.flexible(), spacing: 16, alignment: .leading),
      GridItem(.flexible(), spacing: 16, alignment: .leading),
    ]
  }

  var body: some View {
    ZStack {
      backgroundView

      GeometryReader { proxy in
        ScrollView(showsIndicators: false) {
          VStack(spacing: 0) {
            titleSection
              .padding(.bottom, 51)

            completionCard
              .padding(.bottom, isTrial ? 32 : 12)

            if !isTrial, let streak {
              streakCard(streak)
                .padding(.bottom, 32)
            }

            completedStepsSection

            Spacer(minLength: isTrial ? 32 : 25)

            bottomButtonSection
          }
          .padding(.top, topContentPadding)
          .padding(.horizontal, 20)
          .frame(minHeight: proxy.size.height, alignment: .top)
        }
      }
    }
    .onChange(of: normalizedCompletionRate) { _, newValue in
      withAnimation(.easeOut(duration: 0.8)) {
        animatedProgress = newValue
      }
    }
  }

  private var backgroundView: some View {
    ZStack(alignment: .top) {
      LinearGradient(
        colors: [
          Color(red: 230 / 255, green: 237 / 255, blue: 255 / 255),
          MoruPilotColor.canvas,
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      Image(AppImage.moruGradientGlow)
        .resizable()
        .frame(width: 393, height: 450)
        .offset(y: -47)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    .ignoresSafeArea()
  }

  private var titleSection: some View {
    VStack(spacing: 4) {
      Text(isTrial ? "루틴 체험 완료!" : "오늘 루틴 완료!")
        .routineFinishedTextStyle(.h2)
        .foregroundStyle(AppColor.gray600)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)

      Text(
        isTrial
          ? "내일 아침부터 함께 해 봐요!"
          : "오늘도 해냈어요! 멋진 하루 시작이에요"
      )
      .routineFinishedTextStyle(.b4)
      .foregroundStyle(AppColor.gray400)
      .lineLimit(nil)
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var completionCard: some View {
    VStack(spacing: 4) {
      Text("오늘 완수율")
        .routineFinishedTextStyle(.c1)
        .foregroundStyle(AppColor.gray350)

      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: 12) {
          completionPercentageView
          progressBar
        }
      } else {
        HStack(alignment: .center, spacing: 8) {
          progressBar
          completionPercentageView
        }
      }
    }
    .padding(16)
    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 220 : 90)
    .background(cardBackground)
    .layoutPriority(1)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("오늘 완수율 \(completionPercentage)퍼센트")
  }

  @ViewBuilder
  private var completionPercentageView: some View {
    let percentage = Text("\(completionPercentage)%")
      .routineFinishedTextStyle(.h3)
      .foregroundStyle(AppColor.gray450)
      .monospacedDigit()
      .fixedSize()

    if dynamicTypeSize.isAccessibilitySize {
      HStack(alignment: .top, spacing: 8) {
        percentage

        Image(systemName: "sparkles")
          .font(.system(size: 22, weight: .medium))
          .foregroundStyle(AppColor.gray250)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, alignment: .center)
    } else {
      ZStack(alignment: .topLeading) {
        percentage

        Image(systemName: "sparkles")
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(AppColor.gray250)
          .offset(x: 57, y: -4)
          .accessibilityHidden(true)
      }
      .frame(width: 83, height: 34, alignment: .leading)
    }
  }

  private var progressBar: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(AppColor.orange150.opacity(0.68))

        Capsule()
          .fill(
            LinearGradient(
              colors: [
                AppColor.orange150,
                MoruPilotColor.accent,
              ],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(width: proxy.size.width * animatedProgress)
      }
    }
    .frame(height: 8)
  }

  private func streakCard(
    _ streak: RoutineStreak
  ) -> some View {
    VStack(spacing: 0) {
      Text("연속 달성")
        .routineFinishedTextStyle(.c1)
        .foregroundStyle(AppColor.gray350)

      Text("\(streak.currentDays)일 연속")
        .routineFinishedTextStyle(.h3)
        .foregroundStyle(AppColor.gray450)
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .frame(maxWidth: .infinity)
    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 172 : 86)
    .background(cardBackground)
    .layoutPriority(1)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "연속 달성 \(streak.currentDays)일 연속, 최고 기록 \(streak.bestDays)일"
    )
    .accessibilityIdentifier("routineFinished.streak")
  }

  @ViewBuilder
  private var completedStepsSection: some View {
    if completedStepTitles.isEmpty {
      Text("완료한 루틴이 없습니다.")
        .routineFinishedTextStyle(.c1)
        .foregroundStyle(AppColor.gray350)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 16)
    } else if isTrial {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(
          Array(completedStepTitles.enumerated()),
          id: \.offset
        ) { _, stepTitle in
          completedStepRow(title: stepTitle)
        }
      }
      .frame(maxWidth: .infinity, alignment: .center)
    } else {
      LazyVGrid(
        columns: stepColumns,
        alignment: .leading,
        spacing: 6
      ) {
        ForEach(
          Array(completedStepTitles.enumerated()),
          id: \.offset
        ) { _, stepTitle in
          completedStepRow(title: stepTitle)
        }
      }
      .padding(.horizontal, 30)
    }
  }

  private func completedStepRow(
    title: String
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
      Image(systemName: "checkmark")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(AppColor.gray350)
        .accessibilityHidden(true)

      Text(title)
        .routineFinishedTextStyle(.c1)
        .foregroundStyle(AppColor.gray350)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("완료, \(title)")
  }

  @ViewBuilder
  private var bottomButtonSection: some View {
    if isTrial {
      finishedButton(
        title: "홈으로",
        foregroundColor: AppColor.grayWhite,
        backgroundColor: MoruPilotColor.accent,
        action: onTapHome
      )
      .padding(.horizontal, 2)
    } else {
      VStack(spacing: 10) {
        finishedButton(
          title: "오늘의 기록 확인",
          foregroundColor: AppColor.gray600,
          backgroundColor: AppColor.grayWhite,
          action: onTapTodayRecord
        )

        finishedButton(
          title: "홈으로",
          foregroundColor: AppColor.grayWhite,
          backgroundColor: MoruPilotColor.accent,
          action: onTapHome
        )
      }
    }
  }

  private func finishedButton(
    title: String,
    foregroundColor: Color,
    backgroundColor: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title)
        .routineFinishedTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 54)
        .background(backgroundColor)
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private var cardBackground: some View {
    RoundedRectangle(
      cornerRadius: MoruPilotRadius.largeCard,
      style: .continuous
    )
    .fill(AppColor.grayWhite.opacity(0.2))
    .overlay {
      RoundedRectangle(
        cornerRadius: MoruPilotRadius.largeCard,
        style: .continuous
      )
      .stroke(
        RadialGradient(
          colors: [
            Color(red: 196 / 255, green: 215 / 255, blue: 255 / 255),
            AppColor.grayWhite,
          ],
          center: .center,
          startRadius: 0,
          endRadius: 240
        ),
        lineWidth: 1
      )
    }
    .shadow(
      color: MoruPilotColor.shadow,
      radius: 7.5
    )
  }
}

private struct RoutineFinishedTextStyleModifier: ViewModifier {
  let style: MoruTextStyle

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric private var scaledLineHeight: CGFloat

  init(style: MoruTextStyle) {
    self.style = style
    _scaledLineHeight = ScaledMetric(
      wrappedValue: style.lineHeight,
      relativeTo: style.relativeTextStyle
    )
  }

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
      .lineHeight(.exact(points: scaledLineHeight.rounded()))
    } else {
      content.moruTextStyle(style)
    }
  }
}

private extension View {
  func routineFinishedTextStyle(_ style: MoruTextStyle) -> some View {
    modifier(RoutineFinishedTextStyleModifier(style: style))
  }
}

#Preview("루틴 완료 화면") {
  RoutineFinishedView(
    completionRate: 1.0,
    streak: RoutineStreak(
      currentDays: 4,
      bestDays: 7,
      completedWeekdays: [.monday, .tuesday]
    ),
    completedStepTitles: [
      "잠자리 정리하기",
      "가볍게 스트레칭하기",
      "심호흡하며 명상하기",
      "짧은 독서 몰입하기",
      "오늘의 다짐 확인하기",
      "감정과 생각을 기록하기",
    ],
    onTapTodayRecord: {
      print("오늘의 기록 확인")
    },
    onTapHome: {
      print("홈으로")
    }
  )
}
