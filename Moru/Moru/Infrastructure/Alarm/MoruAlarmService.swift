//
//  MoruAlarmService.swift
//  Moru
//
//  Created by 김승겸 on 7/12/26.
//

import AlarmKit
import Combine
import SwiftUI

@MainActor
final class MoruAlarmService: ObservableObject {
    @Published private(set) var authorizationState:
        AlarmManager.AuthorizationState

    @Published private(set) var statusMessage =
        "AlarmKit 테스트를 시작해 주세요."

    @Published private(set) var lastScheduledAlarmID: UUID?
    @Published private(set) var lastScheduledDate: Date?

    init() {
        authorizationState =
            AlarmManager.shared.authorizationState
    }

    var authorizationText: String {
        switch authorizationState {
        case .notDetermined:
            return "요청 전"

        case .authorized:
            return "허용됨"

        case .denied:
            return "거부됨"

        @unknown default:
            return "알 수 없음"
        }
    }

    func refreshAuthorizationState() {
        authorizationState =
            AlarmManager.shared.authorizationState
    }

    func requestAuthorization() async {
        refreshAuthorizationState()

        switch authorizationState {
        case .authorized:
            statusMessage = "알람 권한이 이미 허용되어 있습니다."

        case .denied:
            statusMessage = """
            알람 권한이 거부되어 있습니다. \
            설정 앱에서 MORU의 알람 권한을 허용해 주세요.
            """

        case .notDetermined:
            do {
                authorizationState =
                    try await AlarmManager.shared
                        .requestAuthorization()

                switch authorizationState {
                case .authorized:
                    statusMessage =
                        "알람 권한이 허용되었습니다."

                case .denied:
                    statusMessage =
                        "알람 권한이 거부되었습니다."

                case .notDetermined:
                    statusMessage =
                        "알람 권한이 아직 결정되지 않았습니다."

                @unknown default:
                    statusMessage =
                        "알람 권한 상태를 확인할 수 없습니다."
                }
            } catch {
                statusMessage = """
                알람 권한 요청에 실패했습니다.
                \(error.localizedDescription)
                """
            }

        @unknown default:
            statusMessage =
                "알람 권한 상태를 확인할 수 없습니다."
        }
    }

    func scheduleOneTimeAlarm(
        after seconds: TimeInterval,
        routineID: UUID,
        routineName: String
    ) async {
        guard await ensureAuthorization() else {
            return
        }

        let alarmID = UUID()
        let fireDate = Date().addingTimeInterval(seconds)

        let stopButton = AlarmButton(
            text: "알람 끄기",
            textColor: .white,
            systemImageName: "stop.circle.fill"
        )

        let openRoutineButton = AlarmButton(
            text: "루틴 시작",
            textColor: .white,
            systemImageName: "arrow.right.circle.fill"
        )

        let alertPresentation = AlarmPresentation.Alert(
            title: "기상 루틴을 시작할 시간이에요",
            stopButton: stopButton,
            secondaryButton: openRoutineButton,
            secondaryButtonBehavior: .custom
        )

        let metadata = MoruAlarmMetadata(
            alarmID: alarmID.uuidString,
            routineID: routineID.uuidString,
            routineName: routineName
        )

        let attributes = AlarmAttributes<MoruAlarmMetadata>(
            presentation: AlarmPresentation(
                alert: alertPresentation
            ),
            metadata: metadata,
            tintColor: AppColor.babyBlue350
        )

        let openRoutineIntent = OpenMoruRoutineIntent(
            alarmID: alarmID.uuidString,
            routineID: routineID.uuidString
        )

        let configuration =
            AlarmManager
                .AlarmConfiguration<MoruAlarmMetadata>
                .alarm(
                    schedule: .fixed(fireDate),
                    attributes: attributes,
                    secondaryIntent: openRoutineIntent
                )

        do {
            _ = try await AlarmManager.shared.schedule(
                id: alarmID,
                configuration: configuration
            )

            lastScheduledAlarmID = alarmID
            lastScheduledDate = fireDate

            statusMessage = """
            \(fireDate.formatted(date: .omitted, time: .standard))에 \
            알람을 예약했습니다.
            """
        } catch {
            statusMessage = """
            알람 예약에 실패했습니다.
            \(error.localizedDescription)
            """
        }
    }

    func cancelLastScheduledAlarm() {
        guard let alarmID = lastScheduledAlarmID else {
            statusMessage =
                "취소할 테스트 알람이 없습니다."
            return
        }

        do {
            try AlarmManager.shared.cancel(id: alarmID)

            lastScheduledAlarmID = nil
            lastScheduledDate = nil
            statusMessage =
                "테스트 알람 예약을 취소했습니다."
        } catch {
            statusMessage = """
            알람 취소에 실패했습니다.
            \(error.localizedDescription)
            """
        }
    }

    private func ensureAuthorization() async -> Bool {
        refreshAuthorizationState()

        switch authorizationState {
        case .authorized:
            return true

        case .notDetermined:
            await requestAuthorization()
            return authorizationState == .authorized

        case .denied:
            statusMessage = """
            알람 권한이 거부되어 있습니다. \
            설정 앱에서 MORU의 알람 권한을 허용해 주세요.
            """
            return false

        @unknown default:
            statusMessage =
                "알람 권한 상태를 확인할 수 없습니다."
            return false
        }
    }
}
