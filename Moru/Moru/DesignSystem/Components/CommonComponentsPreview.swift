//
//  CommonComponentsPreview.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

#Preview("Moru Common Components") {
  MoruCommonComponentsPreviewHost()
}

private struct MoruCommonComponentsPreviewHost: View {
  @State private var toggleOn = true
  @State private var weekdays: Set<String> = ["월", "화", "수", "목", "금"]
  @State private var tab: MoruTabItem = .home
  @State private var voiceSegment: MoruVoiceSegment = .basic
  @State private var morningRoutineOn = false
  @State private var energyRoutineOn = true
  @State private var voiceCardSelected = true
  @State private var soundTapMessage = "대기 중"

  var body: some View {
    ScrollView {
      VStack(spacing: AppSpacing.xl) {
        MoruButton("다음") {}
        MoruButton("다음", style: .secondary) {}

        VStack(spacing: AppSpacing.sm) {
          ForEach(1...9, id: \.self) { step in
            MoruProgressBar(current: step, total: 9)
          }
        }

        MoruSelectionCard(
          title: "처음이에요",
          subtitle: "루틴을 경험해본 적 없어요",
          isSelected: false
        ) {}

        VStack(spacing: AppSpacing.md) {
          HStack(spacing: AppSpacing.sm) {
            MoruSelectionCard(
              title: "활력",
              subtitle: "에너지 넘치는\n하루 시작",
              isSelected: false,
              style: .compact,
              icon: .energy
            ) {}

            MoruSelectionCard(
              title: "건강",
              subtitle: "몸과 마음을\n챙기는 루틴",
              isSelected: false,
              style: .compact,
              icon: .health
            ) {}
          }

          HStack(spacing: AppSpacing.sm) {
            MoruSelectionCard(
              title: "마음 안정",
              subtitle: "차분하고\n평온한 아침",
              isSelected: false,
              style: .compact,
              icon: .mind
            ) {}

            MoruSelectionCard(
              title: "습관 형성",
              subtitle: "꾸준한 생활\n루틴 만들기",
              isSelected: false,
              style: .compact,
              icon: .habit
            ) {}
          }
        }

        VStack(spacing: AppSpacing.sm) {
          MoruRoutineCard(
            title: "명상 루틴",
            description: "3개 항목 ・8분",
            isActive: $morningRoutineOn
          )
          MoruRoutineCard(title: "새 루틴 추가하기", isAddCard: true)
          MoruRoutineCard(
            title: "활력 루틴",
            description: "6개 항목 ・15분",
            isActive: $energyRoutineOn
          )
        }

        MoruRoutineStepRow(
          index: 1,
          title: "잠자리 정리하기",
          subtitle: "확인형 - 1분"
        )
        MoruRoutineStepRow(
          index: 1,
          title: "잠자리 정리하기",
          subtitle: "확인형 - 1분",
          showsSelectControl: false
        )
        MoruVoiceCard(
          name: "민서",
          description: "따뜻한 친구",
          isSelected: $voiceCardSelected
        )
        MoruWeekdaySelector(selectedWeekdays: $weekdays)
        MoruToggle(isOn: $toggleOn)
        MoruCheckBadge(state: .on)
        MoruCheckBadge(state: .off)
        HStack(spacing: AppSpacing.md) {
          MoruSelectControl(style: .minus) {}
          MoruSelectControl(style: .plus) {}
        }
        MoruTimeSettingCard(
          time: "07:00",
          dateDescription: "2026년 5월 9일 토요일"
        )
        MoruTimerStatus(remainingTime: "1:48", title: "남은 시간")
        VStack(spacing: AppSpacing.xs) {
          MoruSoundModule(
            pauseAction: {
              soundTapMessage = "pause"
            },
            stopAction: {
              soundTapMessage = "stop"
            }
          )

          Text(soundTapMessage)
            .font(AppFont.caption1Medium)
            .foregroundStyle(AppColor.moruTextSecondary)
        }
        MoruVoiceSegmentedControl(selection: $voiceSegment)
        MoruDialog(
          title: "이 항목을 건너뛸까요?",
          message: "건너뛰면 현재 루틴은 미완료로 기록돼요.\n"
            + "다음 루틴으로 넘어갈께요.",
          primaryTitle: "계속하기",
          secondaryTitle: "건너뛰기",
          primaryAction: {},
          secondaryAction: {}
        )
        MoruRecordingStatus(isRecording: false)
        MoruTabBar(selection: $tab)
      }
      .padding(AppSpacing.screenHorizontal)
    }
    .background(AppColor.gray100)
  }
}
