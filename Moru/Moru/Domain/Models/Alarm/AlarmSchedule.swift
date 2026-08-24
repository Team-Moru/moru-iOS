//
//  AlarmSchedule.swift
//  Moru
//

import Foundation

struct AlarmSchedule: Identifiable, Codable, Hashable {
  var id: UUID
  var hour: Int
  var minute: Int
  var weekdays: [Weekday]
  var soundName: String
  var isEnabled: Bool
  var includeWeather: Bool
  var includeFortune: Bool

  init(
    id: UUID = UUID(),
    hour: Int,
    minute: Int,
    weekdays: [Weekday],
    soundName: String = "moru-default",
    isEnabled: Bool = true,
    includeWeather: Bool = false,
    includeFortune: Bool = false
  ) {
    self.id = id
    self.hour = hour
    self.minute = minute
    self.weekdays = weekdays
    self.soundName = soundName
    self.isEnabled = isEnabled
    self.includeWeather = includeWeather
    self.includeFortune = includeFortune
  }
}
