//
//  RecommendedRoutineCreationUseCase.swift
//  Moru
//

import Foundation

struct RecommendedRoutineCreationRequest: Equatable {
  var routine: Routine
  var alarmHour: Int
  var alarmMinute: Int
  var selectedWeekdays: Set<Weekday>
}

struct RecommendedRoutineCreationResult: Equatable {
  var routineID: UUID
  var requiresAlarmRepair: Bool
}

enum RecommendedRoutineCreationError: Error, Equatable, LocalizedError {
  case invalidRoutine
  case invalidAlarmTime
  case emptyWeekdays

  var errorDescription: String? {
    switch self {
    case .invalidRoutine:
      return "추천 루틴 내용을 다시 확인해 주세요."
    case .invalidAlarmTime:
      return "알람 시간을 다시 확인해 주세요."
    case .emptyWeekdays:
      return "알람이 울릴 요일을 하나 이상 선택해 주세요."
    }
  }
}

@MainActor
protocol RecommendedRoutineCreationUseCaseProtocol: AnyObject {
  func weekdayConflict(
    for request: RecommendedRoutineCreationRequest
  ) throws -> Set<Weekday>

  func execute(
    _ request: RecommendedRoutineCreationRequest,
    resolvingWeekdayConflict: Bool
  ) async throws -> RecommendedRoutineCreationResult
}

@MainActor
final class RecommendedRoutineCreationUseCase:
  RecommendedRoutineCreationUseCaseProtocol {
  private let routineSettingUseCase: RoutineSettingUseCase

  init(
    routineRepository: any RoutineRepository,
    alarmScheduleMutator: (any AlarmScheduleMutating)? = nil
  ) {
    routineSettingUseCase = RoutineSettingUseCase(
      routineRepository: routineRepository,
      alarmScheduleMutator: alarmScheduleMutator
    )
  }

  func weekdayConflict(
    for request: RecommendedRoutineCreationRequest
  ) throws -> Set<Weekday> {
    try validate(request)
    return try routineSettingUseCase.weekdayConflict(
      for: makeMutation(from: request)
    )
  }

  func execute(
    _ request: RecommendedRoutineCreationRequest,
    resolvingWeekdayConflict: Bool = false
  ) async throws -> RecommendedRoutineCreationResult {
    try validate(request)
    let result = try await routineSettingUseCase.saveRoutine(
      from: makeMutation(from: request),
      resolvingWeekdayConflict: resolvingWeekdayConflict
    )

    return RecommendedRoutineCreationResult(
      routineID: request.routine.id,
      requiresAlarmRepair: result.requiresRepair
    )
  }

  private func validate(_ request: RecommendedRoutineCreationRequest) throws {
    let trimmedName = request.routine.name.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let hasInvalidStep = request.routine.steps.contains { step in
      step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    guard !trimmedName.isEmpty,
          !request.routine.steps.isEmpty,
          !hasInvalidStep else {
      throw RecommendedRoutineCreationError.invalidRoutine
    }

    guard (0...23).contains(request.alarmHour),
          (0...59).contains(request.alarmMinute) else {
      throw RecommendedRoutineCreationError.invalidAlarmTime
    }

    guard !request.selectedWeekdays.isEmpty else {
      throw RecommendedRoutineCreationError.emptyWeekdays
    }
  }

  private func makeMutation(
    from request: RecommendedRoutineCreationRequest
  ) -> RoutineSettingMutation {
    let routine = request.routine

    return RoutineSettingMutation(
      routineID: routine.id,
      name: routine.name,
      summary: routine.summary,
      goalTags: routine.goalTags,
      alarmScheduleID: routine.alarmSchedule?.id,
      hour: request.alarmHour,
      minute: request.alarmMinute,
      selectedWeekdays: request.selectedWeekdays,
      steps: routine.steps
        .sorted { $0.order < $1.order }
        .map { step in
          RoutineStepMutation(
            id: step.id,
            presetItemID: step.presetItemID,
            type: step.type,
            title: step.title,
            instruction: step.instruction,
            estimatedMinutes: Self.roundedMinutes(
              for: step.estimatedSeconds
            ),
            isRequired: step.isRequired
          )
        },
      isActive: true
    )
  }

  private static func roundedMinutes(for estimatedSeconds: Int?) -> Int {
    let seconds = max(0, estimatedSeconds ?? 60)
    return max(1, (seconds + 59) / 60)
  }
}
