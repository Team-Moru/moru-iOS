//
//  Weekday.swift
//  Moru
//

import Foundation

enum Weekday: Int, Codable, CaseIterable, Hashable, Identifiable {
  case sunday = 1
  case monday
  case tuesday
  case wednesday
  case thursday
  case friday
  case saturday

  var id: Int {
    rawValue
  }
}

extension Weekday {
  static let weekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
  static let displayOrder: [Weekday] = [
    .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
  ]

  var shortTitle: String {
    switch self {
    case .sunday:
      return "일"
    case .monday:
      return "월"
    case .tuesday:
      return "화"
    case .wednesday:
      return "수"
    case .thursday:
      return "목"
    case .friday:
      return "금"
    case .saturday:
      return "토"
    }
  }

  var displayOrderIndex: Int {
    Self.displayOrder.firstIndex(of: self) ?? rawValue
  }
}

extension Sequence where Element == Weekday {
  func sortedByDisplayOrder() -> [Weekday] {
    sorted { $0.displayOrderIndex < $1.displayOrderIndex }
  }
}
