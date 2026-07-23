//
//  AlarmRingView.swift
//  Moru
//
//  Created by 김승겸 on 7/7/26.
//

import SwiftUI

private enum AlarmRingAction: Equatable {
  case start
  case snooze(Int)
}

struct AlarmRingView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let routineName: String
  let routineMinutes: Int
  let alarmDate: Date
  let onStartRoutine: @MainActor () async throws -> Void
  let onSnoozeSelected: @MainActor (Int) async throws -> Void

  @State private var isShowingSnoozeSheet = false
  @State private var isProcessing = false
  @State private var errorMessage: String?
  @State private var retryAction: AlarmRingAction?
  @State private var slideResetToken = 0

  init(
    routineName: String,
    routineMinutes: Int,
    alarmDate: Date = Date(),
    onStartRoutine: @escaping @MainActor () async throws -> Void = {},
    onSnoozeSelected: @escaping @MainActor (Int) async throws -> Void = { _ in }
  ) {
    self.routineName = routineName
    self.routineMinutes = routineMinutes
    self.alarmDate = alarmDate
    self.onStartRoutine = onStartRoutine
    self.onSnoozeSelected = onSnoozeSelected
  }

  var body: some View {
    ZStack {
      alarmBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        timeSection

        Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 12 : 28)

        routineSection

        if let errorMessage {
          errorView(message: errorMessage)
            .padding(.top, 20)
        }

        Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 16 : 32)

        SlideToStartControl(isEnabled: !isProcessing) {
          perform(.start)
        }
        .id(slideResetToken)
      }
      .padding(.horizontal, 20)
      .padding(.top, dynamicTypeSize.isAccessibilitySize ? 40 : 88)
      .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 24 : 36)
      .dynamicTypeSize(.xSmall ... .accessibility1)

      if isProcessing {
        ProgressView()
          .tint(.white)
          .padding(18)
          .background(.ultraThinMaterial, in: Circle())
          .accessibilityLabel("알람 요청 처리 중")
      }
    }
    .sheet(isPresented: $isShowingSnoozeSheet) {
      SnoozeSheetView(
        selectedMinutes: 5,
        onConfirm: { minutes in
          isShowingSnoozeSheet = false
          perform(.snooze(minutes))
        },
        onCancel: {
          isShowingSnoozeSheet = false
        }
      )
      .presentationDetents([.height(489)])
      .presentationDragIndicator(.visible)
      .presentationCornerRadius(32)
    }
  }

  private var alarmBackground: some View {
    LinearGradient(
      colors: [
        AppColor.babyBlue100,
        AppColor.babyBlue150,
        AppColor.babyBlue250,
      ],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  private var timeSection: some View {
    VStack(spacing: 16) {
      Text(alarmTimeText)
        .font(AppFont.pretendardSemiBold(size: 80))
        .foregroundStyle(Color.white)
        .minimumScaleFactor(0.7)

      Text(alarmDateText)
        .font(AppFont.body1NormalBold)
        .foregroundStyle(AppColor.grayWhite)
    }
    .accessibilityElement(children: .combine)
  }

  private var routineSection: some View {
    VStack(spacing: 16) {
      AlarmRoutineCardView(
        title: "오늘의 루틴",
        routineName: routineName,
        minutes: routineMinutes
      )

      Button {
        isShowingSnoozeSheet = true
      } label: {
        Text("다시 알림")
          .font(AppFont.label1NormalMedium)
          .foregroundStyle(Color.white)
          .lineLimit(1)
          .frame(width: 132, height: 40)
      }
      .buttonStyle(.plain)
      .disabled(isProcessing)
      .glassEffect(
        .clear.interactive(),
        in: Capsule()
      )
      .overlay {
        Capsule()
          .stroke(Color.white.opacity(0.22), lineWidth: 0.7)
      }
      .contentShape(Capsule())
      .accessibilityHint("5분, 10분, 15분 또는 30분 뒤 다시 알림을 설정합니다.")
    }
  }

  private func errorView(message: String) -> some View {
    VStack(spacing: 8) {
      Text(message)
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.grayWhite)
        .multilineTextAlignment(.center)

      Button("다시 시도") {
        guard let retryAction else {
          return
        }
        perform(retryAction)
      }
      .font(AppFont.label1NormalSemiBold)
      .foregroundStyle(Color.white)
      .disabled(isProcessing)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
    .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
  }

  private var alarmTimeText: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: alarmDate)
  }

  private var alarmDateText: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "yyyy년 M월 d일 EEEE"
    return formatter.string(from: alarmDate)
  }

  private func perform(_ action: AlarmRingAction) {
    guard !isProcessing else {
      return
    }

    isProcessing = true
    errorMessage = nil
    retryAction = action

    Task { @MainActor in
      do {
        switch action {
        case .start:
          try await onStartRoutine()
        case .snooze(let minutes):
          try await onSnoozeSelected(minutes)
        }
      } catch {
        errorMessage = Self.errorMessage(for: action)
        slideResetToken += 1
      }
      isProcessing = false
    }
  }

  private static func errorMessage(for action: AlarmRingAction) -> String {
    switch action {
    case .start:
      "알람을 멈추지 못했어요. 다시 시도해 주세요."
    case .snooze:
      "다시 알림을 설정하지 못했어요. 다시 시도해 주세요."
    }
  }
}

#Preview("Alarm Ring") {
  AlarmRingView(
    routineName: "활력 루틴",
    routineMinutes: 15,
    alarmDate: Calendar.current.date(
      from: DateComponents(
        year: 2026,
        month: 5,
        day: 9,
        hour: 7,
        minute: 0
      )
    ) ?? Date()
  )
}
