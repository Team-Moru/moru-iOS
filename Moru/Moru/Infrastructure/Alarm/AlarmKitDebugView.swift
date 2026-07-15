//
//  AlarmKitDebugView.swift
//  Moru
//
//  Created by 김승겸 on 7/12/26.
//

#if DEBUG

import SwiftUI

struct AlarmKitDebugView: View {
    private enum Phase {
        case alarmControl
        case alarmRing
        case routinePlayer
    }

    let dependencies: DependencyContainer

    @StateObject private var alarmService =
        MoruAlarmService()

    @Environment(\.scenePhase)
    private var scenePhase

    @State private var phase: Phase = .alarmControl

    private let routine = Routine.mockMorningRoutine

    var body: some View {
        Group {
            switch phase {
            case .alarmControl:
                alarmControlView

            case .alarmRing:
                alarmRingView

            case .routinePlayer:
                RoutinePlayerView(
                    routine: routine,
                    dependencies: dependencies
                )
            }
        }
        .onAppear {
            consumePendingAlarmRoute()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            consumePendingAlarmRoute()
        }
    }

    private var alarmControlView: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("AlarmKit 테스트")
                        .font(.title2.bold())

                    Text(
                        "권한 상태: \(alarmService.authorizationText)"
                    )
                    .font(.body)

                    Text(alarmService.statusMessage)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        await alarmService
                            .requestAuthorization()
                    }
                } label: {
                    Text("알람 권한 요청")
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task {
                        await alarmService
                            .scheduleOneTimeAlarm(
                                after: 60,
                                routineID: routine.id,
                                routineName: routine.name
                            )
                    }
                } label: {
                    Text("60초 뒤 테스트 알람 예약")
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    alarmService
                        .cancelLastScheduledAlarm()
                } label: {
                    Text("마지막 테스트 알람 취소")
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.bordered)

                Divider()

                Button {
                    phase = .alarmRing
                } label: {
                    Text("MORU 알람 화면 직접 보기")
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("AlarmKit QA")
        }
    }

    private var alarmRingView: some View {
        AlarmRingView(
            routineName: routine.name,
            routineMinutes: routineMinutes,
            alarmDate: alarmService.lastScheduledDate
                ?? Date(),
            onStartRoutine: {
                phase = .routinePlayer
            },
            onSnoozeSelected: { minutes in
                Task {
                    await alarmService
                        .scheduleOneTimeAlarm(
                            after: TimeInterval(minutes * 60),
                            routineID: routine.id,
                            routineName: routine.name
                        )

                    phase = .alarmControl
                }
            }
        )
    }

    private var routineMinutes: Int {
        let totalSeconds = routine.steps.reduce(0) {
            result,
            step in

            result + (step.estimatedSeconds ?? 60)
        }

        return max(
            1,
            (totalSeconds + 59) / 60
        )
    }

    private func consumePendingAlarmRoute() {
        guard MoruAlarmRouteStore
            .consumePendingRoute() != nil
        else {
            return
        }

        phase = .alarmRing
    }
}

#endif
