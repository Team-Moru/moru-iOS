//
//  ServerRoutineSuggestionService.swift
//  Moru
//

import Foundation

nonisolated enum ServerRoutineSuggestionStepKind: Equatable, Sendable {
  case check
  case timer
  case input
  case unsupported(String)
}

nonisolated struct ServerRoutineSuggestionStep: Equatable, Sendable {
  let title: String
  let kind: ServerRoutineSuggestionStepKind
  let durationSeconds: Int
}

nonisolated struct ServerRoutineSuggestionResponse: Equatable, Sendable {
  let title: String
  let description: String?
  let steps: [ServerRoutineSuggestionStep]
}

nonisolated enum RoutineSuggestionRemoteFailure:
  Error,
  Equatable,
  Sendable {
  case offline
  case timeout
  case serverUnavailable
  case invalidResponse
  case unavailable
  case cancelled
}

/// Domain-owned port for fetching an already mapped server suggestion.
nonisolated protocol ServerRoutineSuggestionFetching: Sendable {
  func generate(
    userInput: String,
    memberID: Int64
  ) async throws
    -> ServerRoutineSuggestionResponse
}

nonisolated enum RoutineSuggestionDraftValidation {
  static let maximumRoutineTitleLength = 80
  static let maximumRoutineDescriptionLength = 500
  static let maximumStepTitleLength = 100
  static let maximumStepCount = 30
  static let validStepDuration = 1...3_600
  static let maximumUserInputLength = 200

  static func isValidUserInput(_ input: String) -> Bool {
    !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && input.utf16.count <= maximumUserInputLength
  }

  static func boundedUserInput(_ input: String) -> String {
    var result = ""
    var usedUTF16Units = 0

    for character in input {
      let characterUnits = String(character).utf16.count
      guard usedUTF16Units + characterUnits <= maximumUserInputLength else {
        break
      }

      result.append(character)
      usedUTF16Units += characterUnits
    }

    return result
  }

  static func isValidRoutineTitle(_ title: String) -> Bool {
    let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return !normalized.isEmpty
      && normalized.count <= maximumRoutineTitleLength
  }

  static func isValidRoutineDescription(_ description: String) -> Bool {
    description.trimmingCharacters(in: .whitespacesAndNewlines).count
      <= maximumRoutineDescriptionLength
  }

  static func isValidStepCount(_ count: Int) -> Bool {
    (1...maximumStepCount).contains(count)
  }

  static func isValidStepTitle(_ title: String) -> Bool {
    let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return !normalized.isEmpty
      && normalized.count <= maximumStepTitleLength
  }

  static func isValidStepDuration(_ seconds: Int?) -> Bool {
    guard let seconds else {
      return false
    }

    return validStepDuration.contains(seconds)
  }

  static func isValidDraft(_ routine: Routine) -> Bool {
    isValidRoutineTitle(routine.name)
      && isValidRoutineDescription(routine.summary)
      && isValidStepCount(routine.steps.count)
      && routine.steps.allSatisfy {
        isValidStepTitle($0.title)
          && isValidStepDuration($0.estimatedSeconds)
      }
  }
}

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
  func makeRoutine(
    from input: RoutineSuggestionInput,
    memberID: Int64
  ) async throws -> Routine
}

@MainActor
final class ServerRoutineSuggestionService: ServerRoutineSuggestionServing {
  private let remoteFetcher: any ServerRoutineSuggestionFetching
  private let now: () -> Date

  init(
    remoteDataSource: any ServerRoutineSuggestionFetching,
    now: @escaping () -> Date = Date.init
  ) {
    self.remoteFetcher = remoteDataSource
    self.now = now
  }

  func makeRoutine(
    from input: RoutineSuggestionInput,
    memberID: Int64
  ) async throws -> Routine {
    let response = try await remoteFetcher.generate(
      userInput: Self.serverInput(from: input),
      memberID: memberID
    )
    try Task.checkCancellation()
    let title = response.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let description = (response.description ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard RoutineSuggestionDraftValidation.isValidRoutineTitle(title) else {
      throw ServerRoutineSuggestionError.invalidRoutineTitle
    }
    guard RoutineSuggestionDraftValidation.isValidRoutineDescription(
      description
    ) else {
      throw ServerRoutineSuggestionError.invalidRoutineDescription
    }
    guard RoutineSuggestionDraftValidation.isValidStepCount(
      response.steps.count
    ) else {
      throw ServerRoutineSuggestionError.invalidStepCount
    }

    let steps = try response.steps.enumerated().map { index, step in
      let stepTitle = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard RoutineSuggestionDraftValidation.isValidStepTitle(
        stepTitle
      ) else {
        throw ServerRoutineSuggestionError.invalidStepTitle(index: index)
      }
      guard let type = Self.stepType(from: step.kind) else {
        throw ServerRoutineSuggestionError.invalidStepType(
          index: index,
          value: step.kind.unsupportedValue ?? "UNKNOWN"
        )
      }
      guard RoutineSuggestionDraftValidation.isValidStepDuration(
        step.durationSeconds
      ) else {
        throw ServerRoutineSuggestionError.invalidStepDuration(
          index: index,
          seconds: step.durationSeconds
        )
      }

      return RoutineStep(
        id: UUID(),
        presetItemID: nil,
        type: type,
        title: stepTitle,
        instruction: "",
        order: index,
        estimatedSeconds: step.durationSeconds,
        isRequired: true
      )
    }
    let date = now()
    try Task.checkCancellation()

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

    let boundedValue = RoutineSuggestionDraftValidation.boundedUserInput(value)
    return boundedValue.isEmpty
      ? "아침 루틴을 추천해 주세요."
      : boundedValue
  }

  private static func stepType(
    from kind: ServerRoutineSuggestionStepKind
  ) -> RoutineStepType? {
    switch kind {
    case .check:
      .confirm
    case .timer:
      .timer
    case .input:
      .input
    case .unsupported:
      nil
    }
  }
}

nonisolated private extension ServerRoutineSuggestionStepKind {
  var unsupportedValue: String? {
    guard case .unsupported(let value) = self else {
      return nil
    }

    return value
  }
}
