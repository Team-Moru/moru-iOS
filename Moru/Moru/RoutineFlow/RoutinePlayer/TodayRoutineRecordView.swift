//
//  TodayRoutineRecordView.swift
//  Moru
//
//  Created by 김승겸 on 7/16/26.
//

import SwiftUI
import UIKit

struct TodayRoutineRecordView: View {

    // MARK: - Input Data

    /// 기록을 표시할 날짜
    let date: Date

    /// 루틴 완수율
    /// 0.0부터 1.0 사이의 값으로 전달
    /// 예: 100% = 1.0, 80% = 0.8
    let completionRate: Double

    /// 루틴 전체 수행 시간
    /// 초 단위로 전달
    /// 예: 11분 12초 = 672초
    let totalDurationSeconds: Int

    /// 사용자가 실제로 기상한 시간
    let wakeUpTime: Date

    /// 루틴에 포함된 모든 항목의 실행 결과
    let results: [RoutineStepResult]

    // MARK: - Navigation Actions

    /// 뒤로 버튼을 눌렀을 때 호출
    /// 상위 화면에서 RoutineFinishedView로 전환하도록 처리
    let onTapBack: () -> Void

    /// 홈으로 버튼을 눌렀을 때 호출
    let onTapHome: () -> Void

    // MARK: - Filtered Results

    /// 전체 루틴 결과 중 입력형 항목만 필터링
    /// 오늘의 기록 영역에서는 사용자가 말하거나 입력한 내용이 있는
    /// 입력형 루틴만 표시
    private var inputResults: [RoutineStepResult] {
        results.filter {
            $0.stepType == .input
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // 화면 전체 배경색
            AppColor.babyBlue50
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    navigationHeader
                        .padding(.bottom, 20)

                    summaryCard
                        .padding(.bottom, 40)

                    todayRecordSection
                        .padding(.bottom, 40)

                    stepResultSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            fixedHomeButton
        }
    }

    // MARK: - Navigation Header

    /// 화면 상단의 내비게이션 영역
    private var navigationHeader: some View {
        ZStack {
            // 가운데 날짜 표시
            Text(formattedDate)
                .font(AppFont.body1NormalSemiBold)
                .foregroundStyle(AppColor.gray600)

            // 왼쪽 뒤로 버튼
            HStack {
                Button {
                    onTapBack()
                } label: {
                    Text("뒤로")
                        .font(AppFont.body1NormalMedium)
                        .foregroundStyle(AppColor.gray350)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .frame(height: 44)
        .padding(.top, 12)
    }

    // MARK: - Routine Summary
    /// 완수율, 전체 소요 시간, 기상 시간을 표시하는 요약 카드
    /// 완수율, 전체 소요 시간, 기상 시간을 표시하는 요약 카드
    private var summaryCard: some View {
        HStack(spacing: 0) {
            // SF Symbol 사용
            summaryItem(
                icon: .system("checkmark"),
                value: completionRateText,
                title: "완수"
            )

            summaryDivider

            // SF Symbol 사용
            summaryItem(
                icon: .system("clock"),
                value: totalDurationText,
                title: "소요"
            )

            summaryDivider

            // AppIcon 커스텀 이미지 사용
            summaryItem(
                icon: .asset(AppIcon.iconSunHaze),
                value: wakeUpTimeText,
                title: "기상"
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .background {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .fill(AppColor.orange250)
        }
    }
    
    private enum SummaryIcon {
        case system(String)
        case asset(String)
    }

    /// 요약 카드 내부의 공통 항목을 생성
    /// SF Symbol과 AppIcon 커스텀 이미지를 모두 지원
    private func summaryItem(
        icon: SummaryIcon,
        value: String,
        title: String
    ) -> some View {
        VStack(spacing: 4) {
            summaryIcon(icon)

            Text(value)
                .font(AppFont.title1Bold)
                .foregroundStyle(AppColor.grayWhite)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .font(AppFont.caption1Medium)
                .foregroundStyle(AppColor.gray350)
        }
        .frame(maxWidth: .infinity)
    }
    
    /// 전달받은 아이콘 종류에 따라
    /// SF Symbol 또는 AppIcon 이미지를 표시
    @ViewBuilder
    private func summaryIcon(
        _ icon: SummaryIcon
    ) -> some View {
        switch icon {
        case .system(let systemName):
            Image(systemName: systemName)
                .font(
                    .system(
                        size: 17,
                        weight: .regular
                    )
                )
                .foregroundStyle(AppColor.orange100)
                .frame(width: 20, height: 20)

        case .asset(let assetName):
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        }
    }

    /// 요약 카드 내부 항목 사이의 세로 구분선
    private var summaryDivider: some View {
        Rectangle()
            .fill(AppColor.grayWhite.opacity(0.42))
            .frame(width: 1, height: 74)
    }

    // MARK: - Today Record Section
    /// 사용자가 수행한 입력형 루틴의 기록을 표시
    private var todayRecordSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("오늘의 기록")

            // 수행한 입력형 항목이 없는 경우 빈 상태를 표시
            if inputResults.isEmpty {
                emptyInputRecordView
            } else {
                // 입력형 항목마다 기록 카드를 생성
                VStack(spacing: 14) {
                    ForEach(inputResults) { result in
                        inputRecordCard(result)
                    }
                }
            }
        }
    }

    /// 오늘 작성된 입력형 기록이 없을 때 표시하는 빈 상태 화면
    private var emptyInputRecordView: some View {
        Text("오늘 작성한 기록이 없습니다.")
            .font(AppFont.label1NormalMedium)
            .foregroundStyle(AppColor.gray350)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(cardBackground)
    }

    /// 입력형 루틴의 인식 결과를 표시하는 카드
    /// 상단에는 항목 이름과 수행 시간을 표시
    /// 하단에는 인식된 문장과 복사·공유 버튼을 표시
    private func inputRecordCard(
        _ result: RoutineStepResult
    ) -> some View {
        VStack(spacing: 0) {
            // 입력형 항목 이름과 수행 시간
            inputRecordHeader(result)

            Divider()
                .overlay(AppColor.gray150)

            HStack(alignment: .bottom, spacing: 12) {
                // 화면에 표시할 인식 결과
                Text(recognizedText(for: result))
                    .font(AppFont.label1NormalMedium)
                    .foregroundStyle(AppColor.gray400)
                    .lineSpacing(5)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )

                // 기록 복사 및 공유 기능
                HStack(spacing: 10) {
                    // MARK: Copy Button

                    Button {
                        // 인식된 텍스트를 시스템 클립보드에 복사
                        UIPasteboard.general.string =
                            recordText(for: result)
                    } label: {
                        Image(AppIcon.iconCopy)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("기록 복사")

                    // MARK: Share Button

                    // ShareLink를 사용해 iOS 기본 공유 시트를 표시
                    ShareLink(
                        item: recordText(for: result)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(AppColor.gray250)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("기록 공유")
                }
                .font(
                    .system(
                        size: 16,
                        weight: .regular
                    )
                )
                .foregroundStyle(AppColor.gray250)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .background(cardBackground)
    }

    /// 클립보드 복사 및 공유에 사용할 원본 텍스트를 반환
    /// transcript가 있으면 transcript를 우선 사용하고,
    /// 없으면 inputText를 사용
    private func recordText(
        for result: RoutineStepResult
    ) -> String {
        let transcript = result.transcript?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if let transcript,
           !transcript.isEmpty {
            return transcript
        }

        let inputText = result.inputText?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if let inputText,
           !inputText.isEmpty {
            return inputText
        }

        return "인식된 내용이 없습니다."
    }

    /// 입력형 기록 카드의 상단 영역입니다.
    /// 완수 아이콘, 항목 이름, 수행 시간을 표시
    private func inputRecordHeader(
        _ result: RoutineStepResult
    ) -> some View {
        HStack(spacing: 10) {
            completionIcon(
                isCompleted: result.isCompleted
            )

            Text(result.stepTitle)
                .font(AppFont.body1NormalSemiBold)
                .foregroundStyle(AppColor.gray550)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(
                "입력형 · \(durationText(result.durationSeconds))"
            )
            .font(AppFont.caption1Medium)
            .foregroundStyle(AppColor.gray350)
            .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    // MARK: - Step Result Section

    /// 전체 루틴 항목의 완수 여부를 표시
    private var stepResultSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("항목별 결과")

            VStack(spacing: 12) {
                ForEach(results) { result in
                    stepResultRow(result)
                }
            }
        }
    }

    /// 루틴 항목 하나의 실행 결과를 표시
    /// 완수 여부, 항목 이름, 항목 유형과 수행 결과를 표시
    private func stepResultRow(
        _ result: RoutineStepResult
    ) -> some View {
        HStack(spacing: 10) {
            completionIcon(
                isCompleted: result.isCompleted
            )

            Text(result.stepTitle)
                .font(AppFont.body1NormalSemiBold)
                .foregroundStyle(AppColor.gray550)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(stepInformationText(result))
                .font(AppFont.caption1Medium)
                .foregroundStyle(AppColor.gray350)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(cardBackground)
    }

    // MARK: - Fixed Bottom Button

    /// 홈으로 버튼
    private var fixedHomeButton: some View {
        VStack(spacing: 0) {
            Button {
                onTapHome()
            } label: {
                Text("홈으로")
                    .font(AppFont.body1NormalSemiBold)
                    .foregroundStyle(AppColor.grayWhite)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(AppColor.orange350)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Common Components

    /// 각 영역의 제목에 공통으로 사용하는 텍스트 스타일
    private func sectionTitle(
        _ title: String
    ) -> some View {
        Text(title)
            .font(AppFont.body1NormalSemiBold)
            .foregroundStyle(AppColor.gray500)
    }

    /// 루틴 항목의 완수 여부를 표시하는 공통 아이콘
    /// 완료된 항목에는 체크 표시,
    /// 완료되지 않은 항목에는 마이너스 표시
    private func completionIcon(
        isCompleted: Bool
    ) -> some View {
        ZStack {
            Circle()
                .stroke(
                    isCompleted
                        ? AppColor.moruBlue
                        : AppColor.gray250,
                    lineWidth: 1.2
                )
                .frame(width: 18, height: 18)

            Image(
                systemName: isCompleted
                    ? "checkmark"
                    : "minus"
            )
            .font(
                .system(
                    size: isCompleted ? 9 : 8,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                isCompleted
                    ? AppColor.moruBlue
                    : AppColor.gray300
            )
        }
    }

    /// 오늘의 기록 카드와 항목별 결과 카드에 공통으로 사용하는 배경
    private var cardBackground: some View {
        RoundedRectangle(
            cornerRadius: 22,
            style: .continuous
        )
        .fill(AppColor.grayWhite.opacity(0.78))
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                AppColor.grayWhite.opacity(0.95),
                lineWidth: 1
            )
        }
        .shadow(
            color: AppColor.babyBlue250.opacity(0.13),
            radius: 12,
            y: 5
        )
    }

    // MARK: - Summary Formatting

    /// 0.0부터 1.0 사이의 완수율을 퍼센트 문자열로 변환합
    /// 범위를 벗어난 값이 들어와도 0%부터 100% 사이로 제한.
    private var completionRateText: String {
        let clampedRate = min(max(completionRate, 0), 1)
        let percentage = Int((clampedRate * 100).rounded())

        return "\(percentage)%"
    }

    /// 초 단위의 전체 소요 시간을 MM:SS 형식으로 변환
    private var totalDurationText: String {
        let seconds = max(totalDurationSeconds, 0)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        return String(
            format: "%02d:%02d",
            minutes,
            remainingSeconds
        )
    }

    /// 기상 시간을 24시간제 HH:mm 형식으로 변환
    private var wakeUpTimeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"

        return formatter.string(from: wakeUpTime)
    }

    // MARK: - Record Formatting
    /// 상단 날짜를 한국어 월·일·요일 형식으로 변환
    /// 예: 5월 8일 금요일
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"

        return formatter.string(from: date)
    }

    /// 화면에 표시할 입력형 루틴의 인식 결과를 반환
    /// transcript를 우선 사용하며, 값이 없으면 inputText를 사용
    /// 화면 표시용이므로 실제 문장이 있을 때 따옴표를 추가.
    private func recognizedText(
        for result: RoutineStepResult
    ) -> String {
        let transcript = result.transcript?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if let transcript,
           !transcript.isEmpty {
            return "\"\(transcript)\""
        }

        let inputText = result.inputText?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if let inputText,
           !inputText.isEmpty {
            return "\"\(inputText)\""
        }

        return "인식된 내용이 없습니다."
    }

    /// 항목 유형과 수행 상태를 하나의 문자열로 조합합니다.
    /// 예:
    /// - 확인형 · 1분
    /// - 타이머형 · 건너뜀
    /// - 입력형 · 미완료
    private func stepInformationText(
        _ result: RoutineStepResult
    ) -> String {
        let typeText: String

        // 루틴 항목 유형을 한글 문자열로 변환
        switch result.stepType {
        case .confirm:
            typeText = "확인형"

        case .timer:
            typeText = "타이머형"

        case .input:
            typeText = "입력형"
        }

        let statusText: String

        // 건너뛴 항목을 가장 먼저 확인합
        if result.skipped {
            statusText = "건너뜀"

        // 완료된 항목은 실제 수행 시간을 표시
        } else if result.isCompleted {
            statusText = durationText(
                result.durationSeconds
            )

        // 완료되지 않았고 건너뛰지도 않은 경우입
        } else {
            statusText = "미완료"
        }

        return "\(typeText) · \(statusText)"
    }

    /// 초 단위 수행 시간을 읽기 쉬운 한글 형식으로 변환
    /// 예:
    /// - 45초
    /// - 3분
    /// - 2분 18초
    private func durationText(
        _ seconds: Int?
    ) -> String {
        guard let seconds,
              seconds > 0
        else {
            return "시간 미기록"
        }

        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        if minutes == 0 {
            return "\(remainingSeconds)초"
        }

        if remainingSeconds == 0 {
            return "\(minutes)분"
        }

        return "\(minutes)분 \(remainingSeconds)초"
    }
}

// MARK: - Preview

#Preview("오늘의 기록") {
    let calendar = Calendar.current

    // 프리뷰에서 표시할 기준 날짜
    let previewDate = calendar.date(
        from: DateComponents(
            year: 2026,
            month: 5,
            day: 8
        )
    ) ?? Date()

    // 프리뷰에서 표시할 기상 시간
    let previewWakeUpTime = calendar.date(
        from: DateComponents(
            year: 2026,
            month: 5,
            day: 8,
            hour: 7,
            minute: 23
        )
    ) ?? Date()

    TodayRoutineRecordView(
        date: previewDate,
        completionRate: 1.0,
        totalDurationSeconds: 11 * 60 + 12,
        wakeUpTime: previewWakeUpTime,
        results: [
            // 입력형 완료 항목
            RoutineStepResult(
                stepID: UUID(),
                stepTitle: "오늘의 다짐 확인하기",
                stepType: .input,
                completedAt: previewDate,
                transcript: "오늘 하루도 최선을 다하자. 나는 잘할 수 있어!",
                durationSeconds: 90
            ),

            // 긴 인식 결과가 포함된 입력형 완료 항목
            RoutineStepResult(
                stepID: UUID(),
                stepTitle: "감정과 생각을 기록하기",
                stepType: .input,
                completedAt: previewDate,
                transcript: """
                아침에 일찍 일어나니까 하루가 훨씬 길게 느껴졌다. \
                조금 피곤하긴 했지만, 루틴을 끝내고 나서 뿌듯했다.
                """,
                durationSeconds: 138
            ),

            // 확인형 완료 항목
            RoutineStepResult(
                stepID: UUID(),
                stepTitle: "물 한 잔 마시기",
                stepType: .confirm,
                completedAt: previewDate,
                durationSeconds: 60
            ),

            // 타이머형 완료 항목
            RoutineStepResult(
                stepID: UUID(),
                stepTitle: "심호흡하며 명상하기",
                stepType: .timer,
                completedAt: previewDate,
                durationSeconds: 180
            ),

            // 건너뛴 확인형 항목
            RoutineStepResult(
                stepID: UUID(),
                stepTitle: "침구 정리하기",
                stepType: .confirm,
                completedAt: nil,
                skipped: true,
                durationSeconds: nil
            )
        ],
        onTapBack: {
            print("RoutineFinishedView로 돌아가기")
        },
        onTapHome: {
            print("홈 화면으로 이동")
        }
    )
}
