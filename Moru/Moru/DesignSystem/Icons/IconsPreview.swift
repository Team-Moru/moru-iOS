//
//  IconsPreview.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

#Preview("Moru Icons") {
  MoruIconsPreviewHost()
}

private struct MoruIconsPreviewHost: View {
  private let columns = [
    GridItem(.adaptive(minimum: 72), spacing: AppSpacing.md)
  ]

  var body: some View {
    ScrollView {
      LazyVGrid(columns: columns, spacing: AppSpacing.lg) {
        previewItem("status on") {
          MoruRoutineStatusIcon(style: .on)
        }

        previewItem("status off") {
          MoruRoutineStatusIcon(style: .off)
        }

        previewItem("check on") {
          MoruCheckIcon(isOn: true)
        }

        previewItem("check off") {
          MoruCheckIcon(isOn: false)
        }

        previewItem("check") {
          MoruSmallCheckIcon()
        }

        previewItem("minus") {
          MoruSelectIcon(style: .minus)
        }

        previewItem("plus") {
          MoruSelectIcon(style: .plus)
        }

        previewItem("chevron") {
          MoruChevron()
        }

        previewItem("down") {
          MoruChevron(direction: .down)
        }

        previewItem("sound") {
          MoruSoundSymbol()
        }

        previewItem("pause") {
          MoruSoundPauseButtonIcon()
        }

        previewItem("stop") {
          MoruSoundStopButtonIcon()
        }

        previewItem("heart") {
          MoruVoiceHeartIcon()
        }

        previewItem("play") {
          MoruVoicePlayIcon()
        }

        previewItem("tab home") {
          MoruTabIconPreview(name: AppIcon.moruTabHome)
        }

        previewItem("tab routine") {
          MoruTabIconPreview(name: AppIcon.moruTabRoutine)
        }

        previewItem("tab record") {
          MoruTabIconPreview(name: AppIcon.moruTabRecord)
        }

        previewItem("tab my") {
          MoruTabIconPreview(name: AppIcon.moruTabMy)
        }

        previewItem("energy") {
          MoruSelectionIcon(icon: .energy)
        }

        previewItem("mind") {
          MoruSelectionIcon(icon: .mind)
        }

        previewItem("health") {
          MoruSelectionIcon(icon: .health)
        }

        previewItem("habit") {
          MoruSelectionIcon(icon: .habit)
        }

        previewItem("record") {
          MoruVoiceRecordingIcon()
        }

        previewItem("mic") {
          MoruSoundIcon()
        }

        previewItem("fire") {
          MoruFireIcon(size: 36)
        }

        previewItem("note") {
          MoruRoutineNoteIcon(isActive: true)
        }

        previewItem("note off") {
          MoruRoutineNoteIcon(isActive: false)
        }
      }
      .padding(AppSpacing.screenHorizontal)
    }
    .background(AppColor.gray100)
  }

  private func previewItem<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(spacing: AppSpacing.xs) {
      ZStack {
        RoundedRectangle(cornerRadius: AppRadius.md)
          .fill(AppColor.grayWhite)

        content()
      }
      .frame(width: 64, height: 64)

      Text(title)
        .font(AppFont.caption1Medium)
        .foregroundStyle(AppColor.moruTextSecondary)
        .lineLimit(1)
    }
  }
}

private struct MoruTabIconPreview: View {
  let name: String

  var body: some View {
    Image(name)
      .renderingMode(.template)
      .resizable()
      .scaledToFit()
      .foregroundStyle(AppColor.orange350)
      .frame(width: 60, height: 24)
  }
}
