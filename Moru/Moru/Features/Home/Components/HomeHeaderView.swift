//
//  HomeHeaderView.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

private struct HomeCaptureReferenceDateKey: EnvironmentKey {
  static let defaultValue: Date? = nil
}

extension EnvironmentValues {
  /// 시각 캡처 테스트가 인사말 시간대를 고정할 때 쓴다. 제품 코드는 설정하지 않는다.
  var homeCaptureReferenceDate: Date? {
    get { self[HomeCaptureReferenceDateKey.self] }
    set { self[HomeCaptureReferenceDateKey.self] = newValue }
  }
}

struct HomeHeaderView: View {
  let userName: String
  private let fixedDate: Date?
  @Environment(\.homeCaptureReferenceDate) private var captureReferenceDate

  init(userName: String, date: Date? = nil) {
    self.userName = userName
    self.fixedDate = date
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      headerContent(at: fixedDate ?? referenceDate ?? context.date)
    }
  }

  private var referenceDate: Date? {
#if DEBUG
    captureReferenceDate
#else
    nil
#endif
  }

  private func headerContent(at date: Date) -> some View {
    VStack(alignment: .leading, spacing: MoruSpacing.four) {
      Text(greeting(at: date))
        .moruTextStyle(.h3)
        .foregroundStyle(MoruColor.textPrimary)
        .fixedSize(horizontal: false, vertical: true)

      Text(HomeCopy.encouragement)
        .moruTextStyle(.b4)
        .foregroundStyle(MoruColor.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, MoruSpacing.twenty)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    .background(alignment: .bottom) {
      MoruBrandGlow(diameter: 380, intensity: 0.5)
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(y: 31)
    }
    .frame(height: 296)
  }

  private func greeting(at date: Date) -> String {
    HomeGreetingPeriod(date: date).greeting(userName: userName)
  }
}

enum HomeGreetingPeriod: Equatable {
  case dawn
  case morning
  case afternoon
  case evening

  init(date: Date, calendar: Calendar = .current) {
    switch calendar.component(.hour, from: date) {
    case 0..<6:
      self = .dawn
    case 6..<12:
      self = .morning
    case 12..<18:
      self = .afternoon
    default:
      self = .evening
    }
  }

  var text: String {
    switch self {
    case .dawn:
      HomeCopy.dawnGreeting
    case .morning:
      HomeCopy.morningGreeting
    case .afternoon:
      HomeCopy.afternoonGreeting
    case .evening:
      HomeCopy.eveningGreeting
    }
  }

  func greeting(userName: String) -> String {
    let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      return text
    }

    let separator = text.hasSuffix("!") ? "\n" : ",\n"
    return "\(text)\(separator)\(trimmedName)님"
  }
}

#Preview("홈 헤더 · 새벽") {
  HomeHeaderView(userName: "다인", date: homePreviewDate(hour: 5))
    .background(MoruColor.homeCanvasTop)
}

#Preview("홈 헤더 · 아침") {
  HomeHeaderView(userName: "다인", date: homePreviewDate(hour: 8))
    .background(MoruColor.homeCanvasTop)
}

#Preview("홈 헤더 · 점심") {
  HomeHeaderView(userName: "다인", date: homePreviewDate(hour: 13))
    .background(MoruColor.homeCanvasTop)
}

#Preview("홈 헤더 · 저녁") {
  HomeHeaderView(userName: "다인", date: homePreviewDate(hour: 20))
    .background(MoruColor.homeCanvasTop)
}

private func homePreviewDate(hour: Int) -> Date {
  Calendar.current.date(
    bySettingHour: hour,
    minute: 0,
    second: 0,
    of: Date()
  ) ?? Date()
}
