//
//  DebugHistoryDummyData.swift
//  Moru
//
//  Temporary DEBUG-only data for checking the History screen layout.
//

#if DEBUG
import Foundation

enum DebugHistoryDummyData {
    static let isEnabled = true

    @MainActor
    static func makeRepository(
        baseRepository: any RoutineRunRepository,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> any RoutineRunRepository {
        DebugHistoryDummyRunRepository(
            baseRepository: baseRepository,
            runs: makeRuns(calendar: calendar, now: now)
        )
    }

    private static func makeRuns(calendar: Calendar, now: Date) -> [RoutineRun] {
        let routineID = UUID(uuidString: "6D23D474-4500-4DD1-B7B5-6BBE77DBAB91")!
        let steps = makeSteps()
        let today = calendar.startOfDay(for: now)
        let completionPattern: [Double] = [
            1.0, 0.83, 1.0, 0.67, 1.0, 0.83, 0.0,
            1.0, 1.0, 0.67, 1.0, 0.50, 0.83, 1.0,
            0.67, 1.0, 1.0, 0.83, 0.50, 1.0, 0.67,
            1.0, 0.83, 1.0, 0.67, 1.0, 0.50, 0.83
        ]

        return completionPattern.enumerated().compactMap { index, completionRate in
            guard completionRate > 0,
                  let day = calendar.date(byAdding: .day, value: -index, to: today),
                  let startedAt = calendar.date(
                    bySettingHour: 7,
                    minute: wakeMinute(for: index),
                    second: 0,
                    of: day
                  ),
                  let completedAt = calendar.date(
                    byAdding: .second,
                    value: 672 + index * 11,
                    to: startedAt
                  ) else {
                return nil
            }

            return RoutineRun(
                id: UUID(),
                routineID: routineID,
                routineName: "아침 루틴",
                startedAt: startedAt,
                completedAt: completedAt,
                results: makeResults(
                    for: steps,
                    completionRate: completionRate,
                    startedAt: startedAt,
                    calendar: calendar
                ),
                plannedSteps: steps,
                endedEarly: completionRate < 0.5,
                sync: .localOnly
            )
        }
    }

    private static func makeSteps() -> [RoutineStepSnapshot] {
        [
            RoutineStepSnapshot(
                stepID: UUID(uuidString: "5779433E-4D8A-4A77-9A72-89F3D82E7631")!,
                stepTitle: "잠자리 정리하기",
                stepType: .confirm,
                stepOrder: 0,
                estimatedSeconds: 60
            ),
            RoutineStepSnapshot(
                stepID: UUID(uuidString: "C64BC187-A499-453F-B7EF-D5CFF647B019")!,
                stepTitle: "심호흡하며 명상하기",
                stepType: .timer,
                stepOrder: 1,
                estimatedSeconds: 180
            ),
            RoutineStepSnapshot(
                stepID: UUID(uuidString: "A4643B98-66B3-4380-9A55-75878EA131D8")!,
                stepTitle: "오늘의 다짐 확언하기",
                stepType: .input,
                stepOrder: 2
            ),
            RoutineStepSnapshot(
                stepID: UUID(uuidString: "71CB7F13-BEB2-4C93-AE1C-13EF88B21861")!,
                stepTitle: "가볍게 스트레칭하기",
                stepType: .timer,
                stepOrder: 3,
                estimatedSeconds: 180
            ),
            RoutineStepSnapshot(
                stepID: UUID(uuidString: "C1D3220B-F2BF-4B7E-9EE0-67DD9DF8D5EB")!,
                stepTitle: "짧은 독서 몰입하기",
                stepType: .timer,
                stepOrder: 4,
                estimatedSeconds: 300
            ),
            RoutineStepSnapshot(
                stepID: UUID(uuidString: "38453534-EF09-4B31-B2D4-63505CFDB156")!,
                stepTitle: "감정과 생각을 기록하기",
                stepType: .input,
                stepOrder: 5
            )
        ]
    }

    private static func makeResults(
        for steps: [RoutineStepSnapshot],
        completionRate: Double,
        startedAt: Date,
        calendar: Calendar
    ) -> [RoutineStepResult] {
        let completedCount = Int((Double(steps.count) * completionRate).rounded(.down))

        return steps.enumerated().map { index, step in
            let isCompleted = index < completedCount
            let completedAt = isCompleted
                ? calendar.date(byAdding: .second, value: (index + 1) * 72, to: startedAt)
                : nil
            let isSkipped = !isCompleted && step.stepType == .input

            return RoutineStepResult(
                stepID: step.stepID,
                stepTitle: step.stepTitle,
                stepType: step.stepType,
                completedAt: completedAt,
                skipped: isSkipped,
                inputText: step.stepType == .input && isCompleted ? "오늘은 차분하게 시작하기" : nil,
                transcript: transcript(for: step, isCompleted: isCompleted, isSkipped: isSkipped),
                durationSeconds: isCompleted ? step.estimatedSeconds : nil
            )
        }
    }

    private static func transcript(
        for step: RoutineStepSnapshot,
        isCompleted: Bool,
        isSkipped: Bool
    ) -> String? {
        guard step.stepType == .input else {
            return nil
        }

        if isCompleted {
            return step.stepTitle == "오늘의 다짐 확언하기"
                ? "오늘은 차분하게 시작하기"
                : "몸이 가벼워졌고 집중해서 하루를 시작하고 싶다."
        }

        return isSkipped ? nil : "작성 전 종료"
    }

    private static func wakeMinute(for index: Int) -> Int {
        let offsets = [8, 14, 2, 23, 5, 18, 38, 0, 11, 27, 7, 16, 31, 4]
        return offsets[index % offsets.count]
    }
}

@MainActor
private final class DebugHistoryDummyRunRepository: RoutineRunRepository {
    private let baseRepository: any RoutineRunRepository
    private let runs: [RoutineRun]

    init(baseRepository: any RoutineRunRepository, runs: [RoutineRun]) {
        self.baseRepository = baseRepository
        self.runs = runs
    }

    func fetchRuns() throws -> [RoutineRun] {
        (try baseRepository.fetchRuns() + runs).sorted { $0.startedAt > $1.startedAt }
    }

    func fetchRecentRuns(limit: Int) throws -> [RoutineRun] {
        guard limit > 0 else {
            return []
        }

        return Array(try fetchRuns().prefix(limit))
    }

    func fetchRuns(for routineID: UUID) throws -> [RoutineRun] {
        try fetchRuns().filter { $0.routineID == routineID }
    }

    func fetchRuns(from startDate: Date, to endDate: Date) throws -> [RoutineRun] {
        try fetchRuns().filter { $0.startedAt >= startDate && $0.startedAt < endDate }
    }

    func fetchRuns(
        for routineID: UUID,
        from startDate: Date,
        to endDate: Date
    ) throws -> [RoutineRun] {
        try fetchRuns(for: routineID)
            .filter { $0.startedAt >= startDate && $0.startedAt < endDate }
    }

    func latestRun(for routineID: UUID) throws -> RoutineRun? {
        try fetchRuns(for: routineID).first
    }

    func run(id: UUID) throws -> RoutineRun? {
        if let baseRun = try baseRepository.run(id: id) {
            return baseRun
        }

        return runs.first { $0.id == id }
    }

    func saveRun(_ run: RoutineRun) throws {
        try baseRepository.saveRun(run)
    }

    func deleteAllRuns() throws {
        try baseRepository.deleteAllRuns()
    }
}
#endif
