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

    /// 저장된 일반 실행에서 다시 계산한 연속 달성 기록. 체험에는 값이 없다.
    let streak: RoutineStreak?

    /// 실제 완료한 루틴 단계 제목
    let completedStepTitles: [String]

    /// 오늘의 기록 화면으로 이동
    let onTapTodayRecord: () -> Void

    /// 홈 화면으로 이동
    let onTapHome: () -> Void

    @State private var animatedProgress: Double = 0

    private let stepColumns = [
        GridItem(
            .flexible(),
            spacing: 16,
            alignment: .leading
        ),
        GridItem(
            .flexible(),
            spacing: 16,
            alignment: .leading
        ),
    ]

    private var normalizedCompletionRate: Double {
        min(max(completionRate, 0), 1)
    }

    private var completionPercentage: Int {
        Int((normalizedCompletionRate * 100).rounded())
    }

    var body: some View {
        ZStack {
            backgroundView

            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        titleSection
                            .padding(.bottom, 51)

                        completionCard
                            .padding(.bottom, 12)

                        if let streak {
                            streakCard(streak)
                                .padding(.bottom, 32)
                        }

                        completedStepsSection
                            .padding(.bottom, 25)

                        bottomButtonSection
                    }
                    .frame(minHeight: proxy.size.height)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedProgress = normalizedCompletionRate
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
            AppColor.babyBlue50
                .ignoresSafeArea()

            Image(AppImage.moruGradientGlow)
                .resizable()
                .scaledToFit()
                .frame(
                    maxWidth: 360,
                    maxHeight: 360
                )
                .offset(y: 20)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var titleSection: some View {
        VStack(spacing: 4) {
            Text("오늘 루틴 완료!")
                .font(AppFont.title2Bold)
                .foregroundStyle(
                    AppColor.gray650
                )

            Text("오늘도 해냈어요! 멋진 하루 시작이에요")
                .font(AppFont.body1NormalMedium)
                .foregroundStyle(
                    AppColor.gray400
                )
        }
        .multilineTextAlignment(.center)
    }

    private var completionCard: some View {
        VStack(spacing: 4) {
            Text("오늘 완수율")
                .font(AppFont.label1NormalMedium)
                .foregroundStyle(
                    AppColor.gray400
                )

            HStack(
                alignment: .center,
                spacing: 10
            ) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(
                                AppColor.coral100
                                    .opacity(0.65)
                            )

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AppColor.orange150,
                                        AppColor.orange350,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width:
                                    proxy.size.width
                                    * animatedProgress
                            )
                    }
                }
                .frame(height: 8)

                Text("\(completionPercentage)%")
                    .font(
                        AppFont.heading1Bold
                    )
                    .foregroundStyle(
                        AppColor.gray550
                    )
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .padding(16)
        .frame(minHeight: 90)
        .background(cardBackground)
    }

    private func streakCard(
        _ streak: RoutineStreak
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("연속 달성")
                .font(AppFont.label1NormalMedium)
                .foregroundStyle(
                    AppColor.gray400
                )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    currentStreakText(streak.currentDays)

                    Spacer(minLength: 4)

                    bestStreakText(streak.bestDays)
                }

                VStack(alignment: .leading, spacing: 4) {
                    currentStreakText(streak.currentDays)
                    bestStreakText(streak.bestDays)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 86)
        .background(cardBackground)
        .accessibilityIdentifier("routineFinished.streak")
    }

    private func currentStreakText(
        _ days: Int
    ) -> some View {
        Text("\(days)일 연속")
            .font(AppFont.heading1Bold)
            .foregroundStyle(
                AppColor.gray550
            )
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
    }

    private func bestStreakText(
        _ days: Int
    ) -> some View {
        Text("최고 기록 \(days)일")
            .font(AppFont.caption1Medium)
            .foregroundStyle(
                AppColor.gray400
            )
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var completedStepsSection: some View {
        if completedStepTitles.isEmpty {
            Text("완료한 루틴이 없습니다.")
                .font(AppFont.label1NormalMedium)
                .foregroundStyle(
                    AppColor.gray400
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .center
                )
                .padding(.vertical, 16)
        } else {
            LazyVGrid(
                columns: stepColumns,
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(
                    Array(
                        completedStepTitles.enumerated()
                    ),
                    id: \.offset
                ) { _, stepTitle in
                    completedStepRow(
                        title: stepTitle
                    )
                }
            }
            .padding(.horizontal, 30)
        }
    }

    private func completedStepRow(
        title: String
    ) -> some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: 5
        ) {
            Image(
                systemName: "checkmark"
            )
            .font(
                .system(
                    size: 10,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                AppColor.gray400
            )

            Text(title)
                .font(
                    AppFont.label1NormalMedium
                )
                .foregroundStyle(
                    AppColor.gray400
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var bottomButtonSection: some View {
        VStack(spacing: 10) {
            Button {
                onTapTodayRecord()
            } label: {
                Text("오늘의 기록 확인")
                    .font(
                        AppFont.body1NormalSemiBold
                    )
                    .foregroundStyle(
                        AppColor.gray600
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        AppColor.grayWhite
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                onTapHome()
            } label: {
                Text("홈으로")
                    .font(
                        AppFont.body1NormalSemiBold
                    )
                    .foregroundStyle(
                        AppColor.grayWhite
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        AppColor.orange350
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(
            cornerRadius: 24,
            style: .continuous
        )
        .fill(
            AppColor.grayWhite
                .opacity(0.72)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                AppColor.grayWhite.opacity(0.9),
                lineWidth: 1
            )
        }
        .shadow(
            color: AppColor.babyBlue250
                .opacity(0.12),
            radius: 12,
            y: 6
        )
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
