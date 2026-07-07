//
//  CompleteOnboardingUseCase.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation

struct CompleteOnboardingRequest: Hashable {
  var suggestionInput: RoutineSuggestionInput
  var selectedVoice: VoiceProfile

  init(
    suggestionInput: RoutineSuggestionInput,
    selectedVoice: VoiceProfile
  ) {
    self.suggestionInput = suggestionInput
    self.selectedVoice = selectedVoice
  }
}

struct CompleteOnboardingResult: Hashable {
  var profile: LocalProfile
  var routine: Routine
}

enum CompleteOnboardingError: Error, Equatable, LocalizedError {
  case invalidAlarmTime(hour: Int, minute: Int)
  case emptyWeekdays
  case unavailableVoice(String)

  var errorDescription: String? {
    switch self {
    case .invalidAlarmTime:
      return "알람 시간을 다시 확인해 주세요."
    case .emptyWeekdays:
      return "알람이 울릴 요일을 하나 이상 선택해 주세요."
    case .unavailableVoice:
      return "v1에서 사용할 수 있는 로컬 목소리만 선택할 수 있어요."
    }
  }
}

protocol CompleteOnboardingUseCaseProtocol: AnyObject {
  @MainActor
  func execute(_ request: CompleteOnboardingRequest) throws -> CompleteOnboardingResult
}

nonisolated final class CompleteOnboardingUseCase: CompleteOnboardingUseCaseProtocol {
  private let localProfileRepository: any LocalProfileRepository
  private let routineRepository: any RoutineRepository
  private let routineSuggestionService: any RoutineSuggestionService

  init(
    localProfileRepository: any LocalProfileRepository,
    routineRepository: any RoutineRepository,
    routineSuggestionService: any RoutineSuggestionService
  ) {
    self.localProfileRepository = localProfileRepository
    self.routineRepository = routineRepository
    self.routineSuggestionService = routineSuggestionService
  }

  @MainActor
  func execute(_ request: CompleteOnboardingRequest) throws -> CompleteOnboardingResult {
    try validate(request)

    var profile = try localProfileRepository.loadOrCreateDefaultProfile()
    profile.selectedVoice = request.selectedVoice
    profile.updatedAt = Date()
    try localProfileRepository.saveProfile(profile)

    var routine = try routineSuggestionService.makeRoutine(from: request.suggestionInput)
    routine.isActive = true
    routine.alarmSchedule = makeEnabledAlarm(
      from: request.suggestionInput,
      existingAlarm: routine.alarmSchedule
    )
    routine.sync = .localOnly
    routine.updatedAt = Date()
    try routineRepository.saveRoutine(routine)

    return CompleteOnboardingResult(profile: profile, routine: routine)
  }

  @MainActor
  private func validate(_ request: CompleteOnboardingRequest) throws {
    let input = request.suggestionInput

    guard (0...23).contains(input.wakeUpHour),
          (0...59).contains(input.wakeUpMinute) else {
      throw CompleteOnboardingError.invalidAlarmTime(
        hour: input.wakeUpHour,
        minute: input.wakeUpMinute
      )
    }

    guard !input.weekdays.isEmpty else {
      throw CompleteOnboardingError.emptyWeekdays
    }

    guard VoiceProfile.localVoices.contains(request.selectedVoice) else {
      throw CompleteOnboardingError.unavailableVoice(request.selectedVoice.id)
    }
  }

  @MainActor
  private func makeEnabledAlarm(
    from input: RoutineSuggestionInput,
    existingAlarm: AlarmSchedule?
  ) -> AlarmSchedule {
    AlarmSchedule(
      id: existingAlarm?.id ?? UUID(),
      hour: input.wakeUpHour,
      minute: input.wakeUpMinute,
      weekdays: input.weekdays,
      soundName: existingAlarm?.soundName ?? "moru-default",
      isEnabled: true,
      includeWeather: false,
      includeFortune: false
    )
  }
}
