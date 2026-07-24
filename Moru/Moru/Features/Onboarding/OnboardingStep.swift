//
//  OnboardingStep.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
  case experience
  case goals
  case suggestedRoutine
  case duration
  case freeform
  case organizing
  case review
  case alarm
  case voice
  case completion

  var id: Int {
    rawValue
  }

  var progressIndex: Int? {
    switch self {
    case .experience:
      return 1
    case .goals:
      return 2
    case .suggestedRoutine:
      return 3
    case .duration:
      return 4
    case .freeform:
      return 5
    case .organizing:
      return nil
    case .review:
      return 6
    case .alarm:
      return 7
    case .voice:
      return 8
    case .completion:
      return nil
    }
  }

  static let progressTotal = 9

  var next: OnboardingStep? {
    switch self {
    case .experience:
      return .goals
    case .goals:
      return .suggestedRoutine
    case .suggestedRoutine:
      return .duration
    case .duration:
      return .freeform
    case .freeform:
      return .organizing
    case .organizing:
      return .review
    case .review:
      return .alarm
    case .alarm:
      return .voice
    case .voice:
      return .completion
    case .completion:
      return nil
    }
  }

  var previous: OnboardingStep? {
    switch self {
    case .experience:
      return nil
    case .goals:
      return .experience
    case .suggestedRoutine:
      return .goals
    case .duration:
      return .suggestedRoutine
    case .freeform:
      return .duration
    case .organizing:
      return .freeform
    case .review:
      return .organizing
    case .alarm:
      return .review
    case .voice:
      return .alarm
    case .completion:
      return .voice
    }
  }
}
