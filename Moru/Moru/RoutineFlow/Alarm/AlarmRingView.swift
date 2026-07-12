//
//  AlarmRingView.swift
//  Moru
//
//  Created by 김승겸 on 7/7/26.
//

import SwiftUI

struct AlarmRingView: View {
    let routineName: String
    let routineMinutes: Int
    let alarmDate: Date
    let onStartRoutine: () -> Void
    let onSnoozeSelected: (Int) -> Void
    
    @State private var isShowingSnoozeSheet = false
    
    init(
        routineName: String,
        routineMinutes: Int,
        alarmDate: Date = Date(),
        onStartRoutine: @escaping () -> Void = {},
        onSnoozeSelected: @escaping (Int) -> Void = { _ in }
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
                Spacer(minLength: 20)

                timeSection

                Spacer(minLength: 28)

                routineSection

                Spacer(minLength: 32)

                SlideToStartControl {
                    onStartRoutine()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $isShowingSnoozeSheet) {
            SnoozeSheetView(
                selectedMinutes: 5,
                onConfirm: { minutes in
                    isShowingSnoozeSheet = false
                    onSnoozeSelected(minutes)
                },
                onCancel: {
                    isShowingSnoozeSheet = false
                }
            )
            .presentationDetents([.height(540)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
    }
    
    private var alarmBackground: some View {
        LinearGradient(
            colors: [
                AppColor.babyBlue100,
                AppColor.babyBlue150,
                AppColor.babyBlue250
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
            
            Text(alarmDateText)
                .font(AppFont.body1NormalBold)
                .foregroundStyle(AppColor.grayWhite)
        }
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
                Text("5분 후 다시 알림")
                    .font(AppFont.label1NormalMedium)
                    .foregroundStyle(AppColor.grayWhite)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .alarmGlass(
                        in: Capsule(),
                        tint: AppColor.grayWhite,
                        opacity: 0.2,
                        strokeOpacity: 0.6
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
        }
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
}

struct AlarmGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color
    let opacity: Double
    let strokeOpacity: Double
    
    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(tint.opacity(opacity))
                    .background(.ultraThinMaterial, in: shape)
            }
            .overlay {
                shape
                    .stroke(AppColor.grayWhite.opacity(strokeOpacity), lineWidth: 1)
            }
            .clipShape(shape)
    }
}

extension View {
    func alarmGlass<S: Shape>(
        in shape: S,
        tint: Color = AppColor.grayWhite,
        opacity: Double = 0.16,
        strokeOpacity: Double = 0.7
    ) -> some View {
        modifier(
            AlarmGlassModifier(
                shape: shape,
                tint: tint,
                opacity: opacity,
                strokeOpacity: strokeOpacity
            )
        )
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
