//
//  OpenMoruRoutineIntent.swift
//  Moru
//
//  Created by 김승겸 on 7/12/26.
//

import AlarmKit
import AppIntents
import Foundation

nonisolated enum MoruAlarmRouteStore {
    private static let pendingAlarmIDKey =
        "moru.pendingAlarmID"

    private static let pendingRoutineIDKey =
        "moru.pendingRoutineID"

    static func savePendingRoute(
        alarmID: String,
        routineID: String
    ) {
        UserDefaults.standard.set(
            alarmID,
            forKey: pendingAlarmIDKey
        )

        UserDefaults.standard.set(
            routineID,
            forKey: pendingRoutineIDKey
        )
    }

    static func consumePendingRoute() -> (
        alarmID: String,
        routineID: String
    )? {
        guard
            let alarmID = UserDefaults.standard.string(
                forKey: pendingAlarmIDKey
            ),
            let routineID = UserDefaults.standard.string(
                forKey: pendingRoutineIDKey
            )
        else {
            return nil
        }

        UserDefaults.standard.removeObject(
            forKey: pendingAlarmIDKey
        )

        UserDefaults.standard.removeObject(
            forKey: pendingRoutineIDKey
        )

        return (
            alarmID: alarmID,
            routineID: routineID
        )
    }
}

public struct OpenMoruRoutineIntent:
    LiveActivityIntent {

    public static let title: LocalizedStringResource =
        "MORU 루틴 시작"

    public static let description =
        IntentDescription(
            "MORU 앱을 열고 기상 루틴 화면으로 이동합니다."
        )

    public static let openAppWhenRun = true

    @Parameter(title: "Alarm ID")
    public var alarmID: String

    @Parameter(title: "Routine ID")
    public var routineID: String

    public init(
        alarmID: String,
        routineID: String
    ) {
        self.alarmID = alarmID
        self.routineID = routineID
    }

    public init() {
        alarmID = ""
        routineID = ""
    }

    public func perform() async throws -> some IntentResult {
        MoruAlarmRouteStore.savePendingRoute(
            alarmID: alarmID,
            routineID: routineID
        )

        return .result()
    }
}
