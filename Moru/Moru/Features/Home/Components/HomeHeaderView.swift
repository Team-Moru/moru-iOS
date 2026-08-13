//
//  HomeHeaderView.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct HomeHeaderView: View {
  let userName: String
  private let fixedDate: Date?

  init(userName: String, date: Date? = nil) {
    self.userName = userName
    self.fixedDate = date
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      headerContent(at: fixedDate ?? context.date)
    }
  }

  private func headerContent(at date: Date) -> some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
      Text(greeting(at: date))
        .homeFigmaTextStyle(.h3)
        .foregroundStyle(MoruPilotColor.textPrimary)
        .fixedSize(horizontal: false, vertical: true)

      Text(HomeCopy.encouragement)
        .homeFigmaTextStyle(.b4)
        .foregroundStyle(MoruPilotColor.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, MoruPilotSpacing.twenty)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    .background(alignment: .bottom) {
      Image(AppImage.moruGradientGlow)
        .resizable()
        .scaledToFit()
        .opacity(0.8)
        .frame(width: 353, height: 404)
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(y: 31)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    .frame(height: 296)
  }

  private func greeting(at date: Date) -> String {
    let greeting = HomeGreetingPeriod(date: date).text
    let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      return greeting
    }

    return "\(greeting),\n\(trimmedName)님"
  }
}

enum HomeGreetingPeriod: Equatable {
  case morning
  case afternoon
  case evening

  init(date: Date, calendar: Calendar = .current) {
    switch calendar.component(.hour, from: date) {
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
    case .morning:
      HomeCopy.morningGreeting
    case .afternoon:
      HomeCopy.afternoonGreeting
    case .evening:
      HomeCopy.eveningGreeting
    }
  }
}

#Preview("홈 헤더 · 아침") {
  HomeHeaderView(userName: "다인", date: homePreviewDate(hour: 8))
    .background(AppColor.babyBlue50)
}

#Preview("홈 헤더 · 점심") {
  HomeHeaderView(userName: "다인", date: homePreviewDate(hour: 13))
    .background(AppColor.babyBlue50)
}

#Preview("홈 헤더 · 저녁") {
  HomeHeaderView(userName: "다인", date: homePreviewDate(hour: 20))
    .background(AppColor.babyBlue50)
}

private func homePreviewDate(hour: Int) -> Date {
  Calendar.current.date(
    bySettingHour: hour,
    minute: 0,
    second: 0,
    of: Date()
  ) ?? Date()
}
