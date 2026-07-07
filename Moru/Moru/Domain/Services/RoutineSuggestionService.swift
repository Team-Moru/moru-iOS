//
//  RoutineSuggestionService.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation

enum RoutineExperience: String, Codable, CaseIterable, Hashable, Identifiable {
  case firstTime
  case wantsRecommendation
  case hasRoutine

  var id: String {
    rawValue
  }
}

struct RoutineSuggestionInput: Hashable {
  var experience: RoutineExperience
  var routineName: String
  var goalTags: [String]
  var selectedKeywords: [String]
  var freeformText: String
  var wakeUpHour: Int
  var wakeUpMinute: Int
  var weekdays: [Weekday]

  init(
    experience: RoutineExperience = .firstTime,
    routineName: String = "",
    goalTags: [String] = [],
    selectedKeywords: [String] = [],
    freeformText: String = "",
    wakeUpHour: Int = 7,
    wakeUpMinute: Int = 0,
    weekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
  ) {
    self.experience = experience
    self.routineName = routineName
    self.goalTags = goalTags
    self.selectedKeywords = selectedKeywords
    self.freeformText = freeformText
    self.wakeUpHour = wakeUpHour
    self.wakeUpMinute = wakeUpMinute
    self.weekdays = weekdays
  }
}

protocol RoutineSuggestionService: AnyObject {
  @MainActor
  func makeRoutine(from input: RoutineSuggestionInput) throws -> Routine
}

final class LocalTemplateSuggestionService: RoutineSuggestionService {
  static let shared = LocalTemplateSuggestionService()

  private init() {}

  func makeRoutine(from input: RoutineSuggestionInput) throws -> Routine {
    let now = Date()
    let template = selectTemplate(for: input)
    let trimmedName = input.routineName.trimmingCharacters(in: .whitespacesAndNewlines)
    let routineName = trimmedName.isEmpty ? template.name : trimmedName
    let alarmSchedule = AlarmSchedule(
      hour: input.wakeUpHour,
      minute: input.wakeUpMinute,
      weekdays: input.weekdays
    )

    return Routine(
      name: routineName,
      summary: template.summary,
      goalTags: input.goalTags,
      steps: template.steps,
      alarmSchedule: alarmSchedule,
      createdAt: now,
      updatedAt: now
    )
  }

  private func selectTemplate(for input: RoutineSuggestionInput) -> LocalRoutineTemplate {
    let normalizedSignals = makeSignals(from: input)

    return Self.templates.max { lhs, rhs in
      let lhsScore = lhs.score(for: normalizedSignals)
      let rhsScore = rhs.score(for: normalizedSignals)

      if lhsScore == rhsScore {
        return lhs.priority > rhs.priority
      }

      return lhsScore < rhsScore
    } ?? Self.templates[0]
  }

  private func makeSignals(from input: RoutineSuggestionInput) -> Set<String> {
    var signals = Set<String>()

    signals.insert(input.experience.rawValue)

    (input.goalTags + input.selectedKeywords).forEach {
      signals.formUnion(Self.normalizedSignals(from: $0))
    }

    signals.formUnion(Self.normalizedSignals(from: input.freeformText))

    return signals
  }

  private static func normalizedSignals(from text: String) -> Set<String> {
    let normalizedText = normalized(text)
    let tokens = text
      .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
      .map(normalized)
      .filter { !$0.isEmpty }

    return Set(([normalizedText, normalizedText.replacingOccurrences(of: " ", with: "")] + tokens)
      .filter { !$0.isEmpty })
  }

  private static func normalized(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  private static let templates: [LocalRoutineTemplate] = [
    LocalRoutineTemplate(
      priority: 0,
      matchSignals: ["energy", "활력", "스트레칭", "물", "기상", "wantsrecommendation"],
      name: "활력 루틴",
      summary: "기상 직후 몸과 마음을 깨우는 로컬 추천 루틴",
      steps: [
        RoutineStep(
          type: .confirm,
          title: "잠자리 정리하기",
          instruction: "이불과 베개를 가볍게 정리해 주세요.",
          order: 0
        ),
        RoutineStep(
          type: .timer,
          title: "심호흡하며 명상하기",
          instruction: "천천히 숨을 들이마시고 내쉬며 몸을 깨워 주세요.",
          order: 1,
          estimatedSeconds: 180
        ),
        RoutineStep(
          type: .input,
          title: "오늘의 다짐 확언하기",
          instruction: "하루 시작 문장을 말하거나 적어 주세요.",
          order: 2
        ),
        RoutineStep(
          type: .timer,
          title: "가볍게 스트레칭하기",
          instruction: "목과 어깨부터 천천히 몸을 풀어 주세요.",
          order: 3,
          estimatedSeconds: 180
        ),
        RoutineStep(
          type: .timer,
          title: "짧은 독서 몰입하기",
          instruction: "짧은 문단 하나를 읽으며 집중을 시작해 주세요.",
          order: 4,
          estimatedSeconds: 300
        ),
        RoutineStep(
          type: .input,
          title: "감정과 생각을 기록하기",
          instruction: "지금 감정과 오늘의 생각을 짧게 남겨 주세요.",
          order: 5,
          estimatedSeconds: 120
        )
      ]
    ),
    LocalRoutineTemplate(
      priority: 1,
      matchSignals: ["health", "건강", "운동", "물마시기", "물 마시기", "물", "스트레칭"],
      name: "건강 루틴",
      summary: "몸을 부드럽게 깨우고 컨디션을 확인하는 로컬 추천 루틴",
      steps: [
        RoutineStep(
          type: .confirm,
          title: "물 한 잔 마시기",
          instruction: "일어나서 물 한 잔으로 몸을 깨워 주세요.",
          order: 0
        ),
        RoutineStep(
          type: .timer,
          title: "가벼운 스트레칭",
          instruction: "목과 어깨부터 천천히 풀어 주세요.",
          order: 1,
          estimatedSeconds: 180
        ),
        RoutineStep(
          type: .input,
          title: "오늘 컨디션 기록",
          instruction: "몸 상태를 한 문장으로 남겨 주세요.",
          order: 2
        )
      ]
    ),
    LocalRoutineTemplate(
      priority: 2,
      matchSignals: ["mind", "마음", "안정", "명상", "일기", "호흡"],
      name: "마음 안정 루틴",
      summary: "차분하게 하루를 시작하도록 돕는 로컬 추천 루틴",
      steps: [
        RoutineStep(
          type: .confirm,
          title: "창문 열고 숨 고르기",
          instruction: "공기를 바꾸고 몸의 긴장을 풀어 주세요.",
          order: 0
        ),
        RoutineStep(
          type: .timer,
          title: "2분 호흡 명상",
          instruction: "편안한 자세로 호흡에 집중해 주세요.",
          order: 1,
          estimatedSeconds: 120
        ),
        RoutineStep(
          type: .input,
          title: "오늘의 마음 기록",
          instruction: "지금 감정을 짧게 말하거나 적어 주세요.",
          order: 2
        )
      ]
    ),
    LocalRoutineTemplate(
      priority: 3,
      matchSignals: ["habit", "습관", "형성", "독서", "루틴", "hasroutine"],
      name: "습관 형성 루틴",
      summary: "작은 행동을 반복하기 쉽게 정리한 로컬 추천 루틴",
      steps: [
        RoutineStep(
          type: .confirm,
          title: "첫 행동 시작하기",
          instruction: "정해둔 첫 행동을 바로 시작해 주세요.",
          order: 0
        ),
        RoutineStep(
          type: .timer,
          title: "집중 준비 시간",
          instruction: "방해 요소를 치우고 오늘 할 일을 떠올려 주세요.",
          order: 1,
          estimatedSeconds: 180
        ),
        RoutineStep(
          type: .input,
          title: "오늘의 작은 약속",
          instruction: "오늘 지킬 작은 습관 하나를 남겨 주세요.",
          order: 2
        )
      ]
    )
  ]
}

private struct LocalRoutineTemplate {
  let priority: Int
  let matchSignals: Set<String>
  let name: String
  let summary: String
  let steps: [RoutineStep]

  init(
    priority: Int,
    matchSignals: Set<String>,
    name: String,
    summary: String,
    steps: [RoutineStep]
  ) {
    self.priority = priority
    self.matchSignals = matchSignals
    self.name = name
    self.summary = summary
    self.steps = steps
  }

  func score(for signals: Set<String>) -> Int {
    matchSignals.intersection(signals).count
  }
}
