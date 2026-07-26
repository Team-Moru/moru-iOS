//
//  ServerRoutineSuggestionService.swift
//  Moru
//

import Foundation

enum ServerRoutineSuggestionError: Error, Equatable, LocalizedError {
  case invalidRoutineTitle
  case invalidRoutineDescription
  case invalidStepCount
  case invalidStepTitle(index: Int)
  case invalidStepType(index: Int, value: String)
  case invalidStepDuration(index: Int, seconds: Int)

  var errorDescription: String? {
    "서버 추천 결과를 안전하게 사용할 수 없어요."
  }
}

@MainActor
protocol ServerRoutineSuggestionServing: AnyObject {
  func makeRoutine(from input: RoutineSuggestionInput) async throws -> Routine
}

@MainActor
final class ServerRoutineSuggestionService: ServerRoutineSuggestionServing {
  private enum Limit {
    static let routineTitle = 80
    static let routineDescription = 500
    static let stepTitle = 100
    static let stepCount = 30
    static let stepDuration = 1...3_600
    static let userInput = 200
  }

  private let remoteDataSource: any RoutineSuggestionRemoteDataSource
  private let now: () -> Date

  init(
    remoteDataSource: any RoutineSuggestionRemoteDataSource,
    now: @escaping () -> Date = Date.init
  ) {
    self.remoteDataSource = remoteDataSource
    self.now = now
  }

  func makeRoutine(from input: RoutineSuggestionInput) async throws -> Routine {
    let response = try await remoteDataSource.generate(
      request: RoutineGroupAiGenerateRequestDTO(
        userInput: Self.serverInput(from: input)
      )
    )
    let title = response.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let description = (response.description ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !title.isEmpty, title.count <= Limit.routineTitle else {
      throw ServerRoutineSuggestionError.invalidRoutineTitle
    }
    guard description.count <= Limit.routineDescription else {
      throw ServerRoutineSuggestionError.invalidRoutineDescription
    }
    guard (1...Limit.stepCount).contains(response.routines.count) else {
      throw ServerRoutineSuggestionError.invalidStepCount
    }

    let steps = try response.routines.enumerated().map { index, step in
      let stepTitle = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !stepTitle.isEmpty, stepTitle.count <= Limit.stepTitle else {
        throw ServerRoutineSuggestionError.invalidStepTitle(index: index)
      }
      guard let type = Self.stepType(from: step.type) else {
        throw ServerRoutineSuggestionError.invalidStepType(
          index: index,
          value: step.type
        )
      }
      guard Limit.stepDuration.contains(step.durationSecond) else {
        throw ServerRoutineSuggestionError.invalidStepDuration(
          index: index,
          seconds: step.durationSecond
        )
      }

      return RoutineStep(
        id: UUID(),
        presetItemID: nil,
        type: type,
        title: stepTitle,
        instruction: "",
        order: index,
        estimatedSeconds: step.durationSecond,
        isRequired: true
      )
    }
    let date = now()

    return Routine(
      id: UUID(),
      name: title,
      summary: description,
      goalTags: input.goalTags,
      steps: steps,
      alarmSchedule: AlarmSchedule(
        id: UUID(),
        hour: input.wakeUpHour,
        minute: input.wakeUpMinute,
        weekdays: input.weekdays
      ),
      isActive: true,
      createdAt: date,
      updatedAt: date,
      sync: .localOnly
    )
  }

  static func serverInput(from input: RoutineSuggestionInput) -> String {
    let components = [
      input.goalTags.joined(separator: ", "),
      input.selectedKeywords.joined(separator: ", "),
      input.freeformText.trimmingCharacters(in: .whitespacesAndNewlines),
    ]
      .filter { !$0.isEmpty }
    let value = components.isEmpty
      ? "아침 루틴을 추천해 주세요."
      : components.joined(separator: " / ")

    return String(value.prefix(Limit.userInput))
  }

  static func validDuration(_ seconds: Int?) -> Bool {
    guard let seconds else {
      return false
    }

    return Limit.stepDuration.contains(seconds)
  }

  private static func stepType(from value: String) -> RoutineStepType? {
    switch value {
    case "CHECK":
      .confirm
    case "TIMER":
      .timer
    case "INPUT":
      .input
    default:
      nil
    }
  }
}
