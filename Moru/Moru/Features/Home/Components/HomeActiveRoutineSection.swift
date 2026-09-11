//
//  HomeActiveRoutineSection.swift
//  Moru
//

import SwiftUI

struct HomeActiveRoutineSection: View {
  let routines: [HomeRoutineState]
  let onOpenSettings: (UUID) -> Void
  let onStartRoutine: (UUID) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      HStack(spacing: AppSpacing.xs) {
        Text(HomeCopy.activeRoutines)
          .moruTextStyle(.b3.weight(.semiBold))
          .foregroundStyle(MoruColor.textPrimary)

        Text("\(routines.count)")
          .moruTextStyle(.c2.weight(.semiBold))
          .foregroundStyle(MoruColor.accent)
          .padding(.horizontal, AppSpacing.sm)
          .padding(.vertical, AppSpacing.xxs)
          .background(AppColor.orange100)
          .clipShape(Capsule())
          .accessibilityHidden(true)

        Spacer()
      }

      if routines.isEmpty {
        emptyState
      } else {
        ForEach(routines) { routine in
          HomeActiveRoutineCard(
            routine: routine,
            onOpenSettings: { onOpenSettings(routine.id) },
            onStartRoutine: { onStartRoutine(routine.id) }
          )
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("home.active-routines.section")
    .accessibilityLabel("활성 루틴 \(routines.count)개")
  }

  private var emptyState: some View {
    Text("추가로 실행할 활성 루틴이 없어요.")
      .moruTextStyle(.c1)
      .foregroundStyle(MoruColor.textSecondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(MoruSpacing.twenty)
      .homePilotSurface()
      .accessibilityIdentifier("home.active-routines.empty")
  }
}

private struct HomeActiveRoutineCard: View {
  let routine: HomeRoutineState
  let onOpenSettings: () -> Void
  let onStartRoutine: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: MoruSpacing.sixteen) {
      settingsButton

      Rectangle()
        .fill(MoruColor.border)
        .frame(height: 1)
        .accessibilityHidden(true)

      progressContent
      startButton
    }
    .padding(MoruSpacing.twenty)
    .homePilotSurface()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("home.active-routine.\(routine.id.uuidString)")
  }

  private var settingsButton: some View {
    Button(action: onOpenSettings) {
      VStack(alignment: .leading, spacing: AppSpacing.sm) {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
          Text(routine.title)
            .moruTextStyle(.b4.weight(.semiBold))
            .foregroundStyle(MoruColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

          activeBadge
          Spacer(minLength: AppSpacing.sm)
          MoruChevron(color: MoruColor.textSecondary)
        }

        routineMetadata
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("home.active-routine.\(routine.id.uuidString).settings")
    .accessibilityLabel("\(routine.title) 설정 열기")
    .accessibilityHint("루틴 설정 화면을 엽니다.")
  }

  @ViewBuilder
  private var routineMetadata: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: AppSpacing.xs) {
        scheduleLabel
        stepSummary
      }
    } else {
      HStack(spacing: AppSpacing.sm) {
        scheduleLabel
        stepSummary
      }
    }
  }

  private var scheduleLabel: some View {
    Label(routine.scheduleText, systemImage: "alarm")
      .moruTextStyle(.c2)
      .foregroundStyle(MoruColor.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var stepSummary: some View {
    Text(routine.stepSummaryText)
      .moruTextStyle(.c2)
      .foregroundStyle(MoruColor.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var activeBadge: some View {
    Text(routine.isActive ? "활성" : "비활성")
      .moruTextStyle(.c2.weight(.semiBold))
      .foregroundStyle(
        routine.isActive ? MoruColor.accent : MoruColor.textSecondary
      )
      .padding(.horizontal, AppSpacing.sm)
      .padding(.vertical, AppSpacing.xxs)
      .background(
        routine.isActive ? MoruColor.accentSurface : MoruColor.surfaceMuted
      )
      .clipShape(Capsule())
  }

  private var progressContent: some View {
    VStack(alignment: .leading, spacing: AppSpacing.xs) {
      HStack {
        Text(routine.statusText)
        Spacer()
        Text(routine.progressText)
      }
      .moruTextStyle(.c2.weight(.semiBold))
      .foregroundStyle(MoruColor.textSecondary)

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(MoruColor.surfaceMuted)

          Capsule()
            .fill(MoruColor.accent)
            .frame(width: proxy.size.width * routine.progress)
        }
      }
      .frame(height: 5)

      Text(routine.completionText)
        .moruTextStyle(.c2)
        .foregroundStyle(MoruColor.textSecondary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("오늘 진행률")
    .accessibilityValue("\(routine.completionText), \(routine.progressText)")
  }

  private var startButton: some View {
    Button(action: onStartRoutine) {
      Text("루틴 시작")
        .moruTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(AppColor.grayWhite)
        .padding(.horizontal, AppSpacing.buttonHorizontal)
        .padding(.vertical, AppSpacing.buttonVertical)
        .frame(maxWidth: .infinity)
        .background(MoruColor.ctaFill)
        .clipShape(RoundedRectangle(cornerRadius: MoruRadius.pill))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("home.active-routine.\(routine.id.uuidString).start")
    .accessibilityLabel("\(routine.title) 시작")
  }
}

#Preview("활성 루틴") {
  HomeActiveRoutineSection(
    routines: [.placeholder],
    onOpenSettings: { _ in },
    onStartRoutine: { _ in }
  )
  .padding()
  .background(AppColor.babyBlue50)
}
