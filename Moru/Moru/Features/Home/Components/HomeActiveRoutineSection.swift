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
        Text("활성 루틴")
          .font(AppFont.pretendardSemiBold(size: 18))
          .foregroundStyle(AppColor.moruTextPrimary)

        Text("\(routines.count)")
          .font(AppFont.caption1SemiBold)
          .foregroundStyle(AppColor.orange350)
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
      .font(AppFont.label1NormalMedium)
      .foregroundStyle(AppColor.moruTextSecondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(AppSpacing.md)
      .background(AppColor.grayWhite.opacity(0.5))
      .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
      .accessibilityIdentifier("home.active-routines.empty")
  }
}

private struct HomeActiveRoutineCard: View {
  let routine: HomeRoutineState
  let onOpenSettings: () -> Void
  let onStartRoutine: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    MoruCard(
      backgroundColor: AppColor.grayWhite,
      shadowColor: AppColor.babyBlue150,
      shadowRadius: 7.5,
      shadowY: 0
    ) {
      settingsButton

      Rectangle()
        .fill(AppColor.moruBorder)
        .frame(height: 1)
        .accessibilityHidden(true)

      progressContent
      startButton
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("home.active-routine.\(routine.id.uuidString)")
  }

  private var settingsButton: some View {
    Button(action: onOpenSettings) {
      VStack(alignment: .leading, spacing: AppSpacing.sm) {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
          Text(routine.title)
            .font(AppFont.body1NormalSemiBold)
            .foregroundStyle(AppColor.moruTextPrimary)
            .fixedSize(horizontal: false, vertical: true)

          activeBadge
          Spacer(minLength: AppSpacing.sm)
          MoruChevron(color: AppColor.moruTextSecondary)
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
      .font(AppFont.caption1Medium)
      .foregroundStyle(AppColor.moruTextSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var stepSummary: some View {
    Text(routine.stepSummaryText)
      .font(AppFont.caption1Medium)
      .foregroundStyle(AppColor.moruTextSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var activeBadge: some View {
    Text(routine.isActive ? "활성" : "비활성")
      .font(AppFont.caption1SemiBold)
      .foregroundStyle(routine.isActive ? AppColor.orange350 : AppColor.moruTextSecondary)
      .padding(.horizontal, AppSpacing.sm)
      .padding(.vertical, AppSpacing.xxs)
      .background(routine.isActive ? AppColor.orange100 : AppColor.moruSurfaceMuted)
      .clipShape(Capsule())
  }

  private var progressContent: some View {
    VStack(alignment: .leading, spacing: AppSpacing.xs) {
      HStack {
        Text(routine.statusText)
        Spacer()
        Text(routine.progressText)
      }
      .font(AppFont.caption1SemiBold)
      .foregroundStyle(AppColor.moruTextSecondary)

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(AppColor.moruSurfaceMuted)

          Capsule()
            .fill(AppColor.orange350)
            .frame(width: proxy.size.width * routine.progress)
        }
      }
      .frame(height: 5)

      Text(routine.completionText)
        .font(AppFont.caption1Medium)
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("오늘 진행률")
    .accessibilityValue("\(routine.completionText), \(routine.progressText)")
  }

  private var startButton: some View {
    Button(action: onStartRoutine) {
      Text("루틴 시작")
        .font(AppFont.pretendardSemiBold(size: 16))
        .foregroundStyle(AppColor.grayWhite)
        .padding(.horizontal, AppSpacing.buttonHorizontal)
        .padding(.vertical, AppSpacing.buttonVertical)
        .frame(maxWidth: .infinity)
        .background(AppColor.orange350)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
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
