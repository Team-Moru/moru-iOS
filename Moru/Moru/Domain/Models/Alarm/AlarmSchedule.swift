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

extension AlarmSchedule {
  /// `date` 이후 이 알람이 울릴 가장 빠른 시각. 꺼져 있거나 반복 요일이 없으면 nil이다.
  /// 같은 시각은 이미 지난 것으로 보고 다음 회차를 돌려준다.
  ///
  /// 요일마다 `Calendar.nextDate`로 다음 회차를 구해 가장 이른 것을 고른다.
  /// 직접 날짜를 더하지 않으므로 서머타임으로 존재하지 않는 벽시계 시각도 달력이 처리한다.
  func nextFireDate(after date: Date, calendar: Calendar = .current) -> Date? {
    guard isEnabled, !weekdays.isEmpty else {
      return nil
    }

    return weekdays
      .compactMap { weekday in
        calendar.nextDate(
          after: date,
          matching: DateComponents(
            hour: hour,
            minute: minute,
            second: 0,
            weekday: weekday.rawValue
          ),
          matchingPolicy: .nextTime
        )
      }
      .min()
  }
}
