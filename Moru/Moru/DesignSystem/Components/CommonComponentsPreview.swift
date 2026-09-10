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
  @State private var tab: MoruTabItem = .home
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

        MoruVoiceCard(
          name: "민서",
          description: "따뜻한 친구",
          isSelected: $voiceCardSelected
        )
        MoruToggle(isOn: $toggleOn)
        MoruCheckBadge(state: .on)
        MoruCheckBadge(state: .off)
        HStack(spacing: AppSpacing.md) {
          MoruSelectControl(style: .minus) {}
          MoruSelectControl(style: .plus) {}
        }
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
            .foregroundStyle(MoruPilotColor.textSecondary)
        }
        MoruDialog(
          title: "이 항목을 건너뛸까요?",
          message: "건너뛰면 현재 루틴은 미완료로 기록돼요.\n"
            + "다음 루틴으로 넘어갈께요.",
          primaryTitle: "계속하기",
          secondaryTitle: "건너뛰기",
          primaryAction: {},
          secondaryAction: {}
        )
        MoruTabBar(selection: $tab)
      }
      .padding(AppSpacing.screenHorizontal)
    }
    .background(AppColor.gray100)
  }
}
