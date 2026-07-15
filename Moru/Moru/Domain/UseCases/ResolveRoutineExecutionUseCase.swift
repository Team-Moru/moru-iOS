//
//  ResolveRoutineExecutionUseCase.swift
//  Moru
//

import Foundation

struct ResolveRoutineExecutionRequest: Equatable {
  enum Launch: Equatable {
    case trial
    case manual
    case scheduled
  }

  let routineID: UUID
  let launch: Launch
}
enum RoutineIneligibilityReason: Equatable {
  case inactive
  case alarmDisabled
  case noExecutableSteps
}

enum RoutineResolutionRetryReason: Equatable {
  case repositoryUnavailable
}

enum RoutineExecutionResolution: Equatable {
  case available(Routine)
  case notFound
  case ineligible(RoutineIneligibilityReason)
  case temporarilyUnavailable(RoutineResolutionRetryReason)
}

@MainActor
protocol ResolveRoutineExecutionUseCaseProtocol: AnyObject {
  func execute(
    _ request: ResolveRoutineExecutionRequest
  ) -> RoutineExecutionResolution
}

@MainActor
final class ResolveRoutineExecutionUseCase: ResolveRoutineExecutionUseCaseProtocol {
  private let routineRepository: any RoutineRepository

  init(routineRepository: any RoutineRepository) {
    self.routineRepository = routineRepository
  }

  func execute(
    _ request: ResolveRoutineExecutionRequest
  ) -> RoutineExecutionResolution {
    let routine: Routine

    do {
      guard let resolvedRoutine = try routineRepository.routine(id: request.routineID) else {
        return .notFound
      }

      routine = resolvedRoutine
    } catch {
      return .temporarilyUnavailable(.repositoryUnavailable)
    }

    guard !routine.steps.isEmpty else {
      return .ineligible(.noExecutableSteps)
    }

    guard request.launch == .scheduled else {
      return .available(routine)
    }

    guard routine.isActive else {
      return .ineligible(.inactive)
    }

    guard routine.alarmSchedule?.isEnabled == true else {
      return .ineligible(.alarmDisabled)
    }

    return .available(routine)
  }
}
