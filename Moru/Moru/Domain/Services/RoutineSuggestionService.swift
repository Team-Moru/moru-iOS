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

/// Supplies the goal-specific item candidates shown while a new user adjusts
/// the initial recommendation. It is intentionally separate from
/// `RoutineSuggestionService`: remote recommendation services only need to
/// return the selected routine, while the bundled preset service can also
/// offer optional local items for the same goal.
@MainActor
protocol RoutineSuggestionItemProviding: AnyObject {
  func recommendationItems(from input: RoutineSuggestionInput) throws -> [RoutinePresetItem]
}

enum RoutineSuggestionError: Error, Equatable {
  case noPresetItems(goal: String)
}

final class LocalTemplateSuggestionService:
  RoutineSuggestionService,
  RoutineSuggestionItemProviding
{
  private static let maximumSuggestedStepCount = 4
  private static let maximumRecommendationCandidateCount = 6

  private let presetProvider: any RoutinePresetProviding

  init(presetProvider: any RoutinePresetProviding) {
    self.presetProvider = presetProvider
  }

  func makeRoutine(from input: RoutineSuggestionInput) throws -> Routine {
    let now = Date()
    let items = try presetProvider.loadItems()
    let template = try selectTemplate(for: input, items: items)
    let trimmedName = input.routineName.trimmingCharacters(in: .whitespacesAndNewlines)
    let routineName = trimmedName.isEmpty ? template.name : trimmedName
    let alarmSchedule = AlarmSchedule(
      hour: input.wakeUpHour,
      minute: input.wakeUpMinute,
      weekdays: input.weekdays
    )
    let steps = template.steps.map {
      RoutineStep(
        presetItemID: $0.presetItemID,
        type: $0.type,
        title: $0.title,
        instruction: $0.instruction,
        order: $0.order,
        estimatedSeconds: $0.estimatedSeconds,
        isRequired: $0.isRequired
      )
    }

    return Routine(
      name: routineName,
      summary: template.summary,
      goalTags: input.goalTags,
      steps: steps,
      alarmSchedule: alarmSchedule,
      createdAt: now,
      updatedAt: now
    )
  }

  func recommendationItems(
    from input: RoutineSuggestionInput
  ) throws -> [RoutinePresetItem] {
    let items = try presetProvider.loadItems()
    let definition = templateDefinition(for: input)
    let matchingItems = try matchingItems(for: definition, from: items)

    return Array(
      prioritizedItems(from: matchingItems)
        .prefix(Self.maximumRecommendationCandidateCount)
    )
  }

  private func selectTemplate(
    for input: RoutineSuggestionInput,
    items: [RoutinePresetItem]
  ) throws -> LocalRoutineTemplate {
    let definition = templateDefinition(for: input)
    let matchingItems = try matchingItems(for: definition, from: items)
    let suggestedItems = suggestedItems(from: matchingItems)

    return LocalRoutineTemplate(
      priority: definition.priority,
      matchSignals: definition.matchSignals,
      name: definition.name,
      summary: definition.summary,
      steps: suggestedItems.enumerated().map { index, item in
        item.makeStep(order: index)
      }
    )
  }

  private func templateDefinition(
    for input: RoutineSuggestionInput
  ) -> RoutineTemplateDefinition {
    if input.goalTags.count == 1,
       let goalTag = input.goalTags.first,
       let definition = Self.templateDefinitions.first(
         where: { $0.goalTag == goalTag }
       ) {
      return definition
    }

    let normalizedSignals = makeSignals(from: input)
    return Self.templateDefinitions.max { lhs, rhs in
      let lhsScore = lhs.score(for: normalizedSignals)
      let rhsScore = rhs.score(for: normalizedSignals)

      if lhsScore == rhsScore {
        return lhs.priority > rhs.priority
      }

      return lhsScore < rhsScore
    } ?? Self.templateDefinitions[0]
  }

  private func matchingItems(
    for definition: RoutineTemplateDefinition,
    from allItems: [RoutinePresetItem]
  ) throws -> [RoutinePresetItem] {
    let matchingItems = allItems.filter { $0.goal == definition.goal }

    guard !matchingItems.isEmpty else {
      throw RoutineSuggestionError.noPresetItems(goal: definition.goal)
    }

    return matchingItems
  }

  private func prioritizedItems(
    from items: [RoutinePresetItem]
  ) -> [RoutinePresetItem] {
    items.filter(\.isCommon) + items.filter { !$0.isCommon }
  }

  /// Preserve the design's common-item-first ordering while ensuring a
  /// first-run routine contains every supported step interaction when the
  /// presets provide one (check, timer, and input).
  private func suggestedItems(
    from matchingItems: [RoutinePresetItem]
  ) -> [RoutinePresetItem] {
    let prioritized = prioritizedItems(from: matchingItems)
    var selected = Array(prioritized.prefix(Self.maximumSuggestedStepCount))

    for type in RoutineStepType.allCases
    where !selected.contains(where: { $0.type == type }) {
      guard let replacement = prioritized.first(where: { candidate in
        candidate.type == type
          && !selected.contains(where: { $0.id == candidate.id })
      }) else {
        continue
      }

      let selectedCounts = Dictionary(grouping: selected, by: \.type)
        .mapValues(\.count)
      guard let replacementIndex = selected.lastIndex(where: {
        (selectedCounts[$0.type] ?? 0) > 1
      }) else {
        continue
      }

      selected[replacementIndex] = replacement
    }

    return selected
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

  private static let templateDefinitions: [RoutineTemplateDefinition] = [
    RoutineTemplateDefinition(
      priority: 0,
      goalTag: "energy",
      goal: "활력",
      matchSignals: ["energy", "활력", "스트레칭", "물", "기상", "wantsrecommendation"],
      name: "활력 루틴",
      summary: "기상 직후 몸과 마음을 깨우는 로컬 추천 루틴"
    ),
    RoutineTemplateDefinition(
      priority: 1,
      goalTag: "health",
      goal: "건강",
      matchSignals: ["health", "건강", "운동", "물마시기", "물 마시기", "물", "스트레칭"],
      name: "건강 루틴",
      summary: "몸을 부드럽게 깨우고 컨디션을 확인하는 로컬 추천 루틴"
    ),
    RoutineTemplateDefinition(
      priority: 2,
      goalTag: "mind",
      goal: "마음 안정",
      matchSignals: ["mind", "마음", "안정", "명상", "일기", "호흡"],
      name: "마음 안정 루틴",
      summary: "차분하게 하루를 시작하도록 돕는 로컬 추천 루틴"
    ),
    RoutineTemplateDefinition(
      priority: 3,
      goalTag: "habit",
      goal: "습관 형성",
      matchSignals: ["habit", "습관", "형성", "독서", "루틴", "hasroutine"],
      name: "습관 형성 루틴",
      summary: "작은 행동을 반복하기 쉽게 정리한 로컬 추천 루틴"
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

private struct RoutineTemplateDefinition {
  let priority: Int
  let goalTag: String
  let goal: String
  let matchSignals: Set<String>
  let name: String
  let summary: String

  func score(for signals: Set<String>) -> Int {
    matchSignals.intersection(signals).count
  }
}
