#if DEBUG

import SwiftUI

struct AlarmKitDebugView: View {
    private enum Phase {
        case alarmControl
        case alarmRing
        case routinePlayer
    }

    let dependencies: DependencyContainer

    @StateObject private var alarmService = MoruAlarmService()

    @Environment(\.scenePhase)
    private var scenePhase

    @State private var phase: Phase = .alarmControl

    private let routine = Routine.mockMorningRoutine

    var body: some View {
        content
            .onAppear {
                consumePendingAlarmRoute()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                consumePendingAlarmRoute()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .alarmControl:
            alarmControlView

        case .alarmRing:
            alarmRingView

        case .routinePlayer:
            routinePlayerPlaceholder
        }
    }

    private var routinePlayerPlaceholder: some View {
        VStack(spacing: 20) {
            Text("루틴 실행 화면")
                .font(.title2.bold())

            Text("RoutinePlayer의 최신 생성 방식으로 연결해야 합니다.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("알람 테스트 화면으로 돌아가기") {
                phase = .alarmControl
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    private var alarmControlView: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("AlarmKit 테스트")
                        .font(.title2.bold())

                    Text("권한 상태: \(alarmService.authorizationText)")
                        .font(.body)

                    Text(alarmService.statusMessage)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        await alarmService.requestAuthorization()
                    }
                } label: {
                    Text("알람 권한 요청")
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task {
                        await alarmService.scheduleOneTimeAlarm(
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
                    alarmService.cancelLastScheduledAlarm()
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
            alarmDate: alarmService.lastScheduledDate ?? Date(),
            onStartRoutine: {
                phase = .routinePlayer
            },
            onSnoozeSelected: { minutes in
                Task {
                    await alarmService.scheduleOneTimeAlarm(
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
        let totalSeconds = routine.steps.reduce(0) { result, step in
            result + (step.estimatedSeconds ?? 60)
        }

        return max(1, (totalSeconds + 59) / 60)
    }

    private func consumePendingAlarmRoute() {
        guard let envelope = AlarmIngressOccurrenceStore.shared
            .claimPendingEnvelope() else {
            return
        }

        AlarmIngressOccurrenceStore.shared.complete(envelope)
        phase = .alarmRing
    }
}

#Preview("AlarmKit Debug") {
    AlarmKitDebugView(
        dependencies: .mock()
    )
}

#endif
