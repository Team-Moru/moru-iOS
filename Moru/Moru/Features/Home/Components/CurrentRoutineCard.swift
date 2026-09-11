//
//  CurrentRoutineCard.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct CurrentRoutineCard: View {
  let routine: HomeRoutineState?
  let onTap: () -> Void
  let onStart: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: MoruSpacing.twelve) {
      Button(action: onTap) {
        HStack {
          Text(HomeCopy.currentRoutine)
            .moruTextStyle(.c1.weight(.semiBold))
            .foregroundStyle(MoruColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

          Spacer()

          MoruChevron(color: MoruColor.textPrimary)
        }
        .frame(minHeight: 22)
      }
      .buttonStyle(.plain)

      if let routine {
        Button(action: onTap) {
          routineSummary(routine)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(summaryAccessibilityLabel(routine))
        .accessibilityHint("루틴 설정을 엽니다.")

        VStack(spacing: AppSpacing.none) {
          ForEach(routine.steps) { step in
            routineStepRow(step)
          }
        }

        MoruButton("루틴 시작", action: onStart)
          .padding(.top, MoruSpacing.four)
      } else {
        emptyState
      }
    }
    .padding(.horizontal, MoruSpacing.twenty)
    .padding(.vertical, MoruSpacing.sixteen)
    .frame(maxWidth: .infinity, alignment: .leading)
    .homePilotSurface()
  }

  private func routineSummary(_ routine: HomeRoutineState) -> some View {
    VStack(alignment: .leading, spacing: MoruSpacing.twelve) {
      nextAlarmRow(routine)

      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
              summaryIndicator
              routineDetails(routine, stacksStatus: true)
            }

            progressRing(routine)
              .frame(maxWidth: .infinity, alignment: .trailing)
          }
        } else {
          HStack(spacing: AppSpacing.md) {
            summaryIndicator
            routineDetails(routine, stacksStatus: false)
            Spacer()
            progressRing(routine)
          }
        }
      }
    }
    .padding(.horizontal, MoruSpacing.sixteen)
    .padding(.vertical, MoruSpacing.twelve)
    .frame(minHeight: 72)
    .background(MoruColor.accentSurface)
    .clipShape(RoundedRectangle(cornerRadius: MoruRadius.card))
  }

  /// 카드의 주인공. 다음에 알람이 울리는 시각과 그 알람이 실제로 예약돼 있는지를 함께 보여 준다.
  @ViewBuilder
  private func nextAlarmRow(_ routine: HomeRoutineState) -> some View {
    let alarmText = routine.nextAlarmText ?? routine.scheduleText

    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: AppSpacing.xs) {
        nextAlarmTime(alarmText)

        if let delivery = routine.alarmDelivery {
          deliveryBadge(delivery)
        }
      }
    } else {
      HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
        nextAlarmTime(alarmText)

        Spacer(minLength: AppSpacing.xs)

        if let delivery = routine.alarmDelivery {
          deliveryBadge(delivery)
        }
      }
    }
  }

  private func nextAlarmTime(_ text: String) -> some View {
    Text(text)
      .moruTextStyle(.b3.weight(.semiBold))
      .foregroundStyle(MoruColor.textStrong)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// 색만으로 상태를 말하지 않도록 주의가 필요한 경우에만 기호를 함께 둔다.
  private func deliveryBadge(_ delivery: HomeAlarmDeliveryState) -> some View {
    HStack(spacing: AppSpacing.xxs) {
      if delivery.needsAttention {
        Image(systemName: "exclamationmark.circle.fill")
          .imageScale(.small)
          .accessibilityHidden(true)
      }

      Text(delivery.text)
        .fixedSize(horizontal: false, vertical: true)
    }
    .moruTextStyle(.c2.weight(.semiBold))
    .foregroundStyle(
      delivery.needsAttention ? MoruColor.textStrong : MoruColor.textSecondary
    )
    .padding(.horizontal, AppSpacing.sm)
    .padding(.vertical, AppSpacing.xxs)
    .background(AppColor.grayWhite)
    .clipShape(Capsule())
  }

  private func summaryAccessibilityLabel(_ routine: HomeRoutineState) -> String {
    [
      routine.title,
      routine.nextAlarmText ?? routine.scheduleText,
      routine.alarmDelivery?.text,
      routine.statusText,
    ]
      .compactMap { $0 }
      .joined(separator: ", ")
  }

  private var summaryIndicator: some View {
    Rectangle()
      .fill(AppColor.orange350)
      .frame(width: 2)
      .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 112 : 41)
  }

  @ViewBuilder
  private func routineDetails(
    _ routine: HomeRoutineState,
    stacksStatus: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if stacksStatus {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
          routineTitle(routine)
          routineStatus(routine)
        }
      } else {
        HStack(spacing: AppSpacing.sm) {
          routineTitle(routine)
          routineStatus(routine)
        }
      }

      Text(routine.estimatedDurationText)
        .moruTextStyle(.c2)
        .foregroundStyle(MoruColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func routineTitle(_ routine: HomeRoutineState) -> some View {
    Text(routine.title)
      .moruTextStyle(.b4.weight(.semiBold))
      .foregroundStyle(MoruColor.textPrimary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func routineStatus(_ routine: HomeRoutineState) -> some View {
    Text(routine.statusText)
      .moruTextStyle(.c2)
      .foregroundStyle(MoruColor.accent)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, AppSpacing.sm)
      .padding(.vertical, AppSpacing.xxs)
      .background(AppColor.grayWhite)
      .clipShape(Capsule())
  }

  private func progressRing(_ routine: HomeRoutineState) -> some View {
    ZStack {
      Circle()
        .stroke(AppColor.orange150, lineWidth: 3)
        .frame(width: progressRingSize, height: progressRingSize)

      Circle()
        .trim(from: 0, to: routine.progress)
        .stroke(
          LinearGradient(
            stops: [
              Gradient.Stop(color: AppColor.orange200, location: 0.00),
              Gradient.Stop(color: AppColor.orange350, location: 1.00),
            ],
            startPoint: UnitPoint(x: 0.57, y: -0.06),
            endPoint: UnitPoint(x: 1, y: 0.25)
          ),
          style: StrokeStyle(lineWidth: 3, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .frame(width: progressRingSize, height: progressRingSize)

      Text(routine.progressText)
        .moruTextStyle(.c1.weight(.semiBold))
        .foregroundStyle(MoruColor.accent)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("루틴 진행률")
    .accessibilityValue(routine.progressText)
  }

  private var progressRingSize: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 96 : 48
  }

  @ViewBuilder
  private func routineStepRow(_ step: HomeRoutineStepState) -> some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
          HStack(alignment: .top, spacing: AppSpacing.sm) {
            MoruCheckBadge(state: step.isCompleted ? .on : .off)
            stepTitle(step)
          }

          stepDetail(step)
            .padding(.leading, 28)
        }
      } else {
        HStack(spacing: AppSpacing.sm) {
          MoruCheckBadge(state: step.isCompleted ? .on : .off)
          stepTitle(step)
          Spacer()
          stepDetail(step)
        }
      }
    }
    .padding(.vertical, MoruSpacing.twelve)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(MoruColor.border)
        .frame(height: 1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(step.title)
    .accessibilityValue(step.accessibilityValue)
  }

  private func stepTitle(_ step: HomeRoutineStepState) -> some View {
    Text(step.title)
      .moruTextStyle(.c1)
      .foregroundStyle(MoruColor.textPrimary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func stepDetail(_ step: HomeRoutineStepState) -> some View {
    Text(step.displayDetail)
      .moruTextStyle(.c2)
      .foregroundStyle(MoruColor.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: MoruSpacing.twelve) {
      Text("오늘 사용할 루틴이 아직 없어요.")
        .moruTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruColor.textPrimary)

      Text("루틴 탭에서 아침 루틴을 설정해보세요.")
        .moruTextStyle(.c1)
        .foregroundStyle(MoruColor.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

#Preview {
  CurrentRoutineCard(
    routine: .placeholder,
    onTap: {},
    onStart: {}
  )
  .padding()
  .background(AppColor.babyBlue50)
}
