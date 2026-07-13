//
//  RoutinePreset.swift
//  Moru
//

import Foundation

struct RoutinePresetItem: Identifiable, Hashable {
  let id: String
  let goal: String
  let title: String
  let type: RoutineStepType
  let estimatedSeconds: Int
  let isCommon: Bool

  func makeStep(order: Int) -> RoutineStep {
    RoutineStep(
      type: type,
      title: title,
      order: order,
      estimatedSeconds: estimatedSeconds
    )
  }
}

protocol RoutinePresetProviding {
  func loadItems() throws -> [RoutinePresetItem]
}
