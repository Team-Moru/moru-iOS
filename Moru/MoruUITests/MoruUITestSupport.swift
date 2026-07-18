import XCTest

enum MoruLedgerFixture: String, CaseIterable {
  case launchSlow = "launch-slow"
  case onboardingExperience = "onboarding-experience"
  case onboardingCompletion = "onboarding-completion"
  case trialStep = "trial-step"
  case trialInput = "trial-input"
  case trialComplete = "trial-complete"
  case homeWeatherFresh = "home-weather-fresh"
  case profileRoot = "profile-root"
  case alarmPermissionOff = "alarm-permission-off"
  case voiceSelection = "voice-selection"
  case notificationDowngrade = "notification-downgrade"
  case regularComplete = "regular-complete"
  case historyDashboard = "history-dashboard"
  case historyWeekly = "history-weekly"
  case historyDetail = "history-detail"
  case componentsDefault = "components-default"
  case absenceAudit = "absence-audit"
  private static let figmaFileURL =
    "https://www.figma.com/design/vrVBDLEy0UmqlLVfxnUcY9/moru"

  var figmaNodeIDs: [String] {
    switch self {
    case .launchSlow:
      ["2644-2640"]
    case .onboardingExperience, .onboardingCompletion:
      ["1666-3219"]
    case .trialStep:
      ["2753-9706"]
    case .trialInput:
      ["2323-3246"]
    case .trialComplete:
      ["2323-3265", "2644-2839"]
    case .homeWeatherFresh:
      ["2045-1840"]
    case .profileRoot:
      ["1948-3859"]
    case .alarmPermissionOff:
      ["2092-4936"]
    case .voiceSelection:
      ["2092-4288"]
    case .notificationDowngrade:
      ["1656-1184", "1851-4683"]
    case .regularComplete:
      ["1656-1043"]
    case .historyDashboard:
      ["1851-3687"]
    case .historyWeekly:
      ["1851-4120"]
    case .historyDetail:
      ["2022-2044", "2564-4072"]
    case .componentsDefault:
      ["1445-1113"]
    case .absenceAudit:
      ["1947-2176"]
    }
  }

  var figmaURLs: [String] {
    figmaNodeIDs.map { nodeID in
      let queryNodeID = nodeID.replacingOccurrences(of: "-", with: ":")
      return "\(Self.figmaFileURL)?node-id=\(queryNodeID)"
    }
  }
}

enum MoruLedgerVariant: CaseIterable {
  case lightMedium
  case lightAccessibility3
  case darkMedium
  case darkAccessibility3

  var interfaceStyle: String {
    switch self {
    case .lightMedium, .lightAccessibility3:
      "Light"
    case .darkMedium, .darkAccessibility3:
      "Dark"
    }
  }

  var contentSizeCategory: String {
    switch self {
    case .lightMedium, .darkMedium:
      "UICTContentSizeCategoryM"
    case .lightAccessibility3, .darkAccessibility3:
      "UICTContentSizeCategoryAccessibilityXL"
    }
  }
  var dynamicTypeProbeValue: String {
    switch self {
    case .lightMedium, .darkMedium:
      "M"
    case .lightAccessibility3, .darkAccessibility3:
      "AX3"
    }
  }

  var baselineName: String {
    switch self {
    case .lightMedium:
      "light-M"
    case .lightAccessibility3:
      "light-AX3"
    case .darkMedium:
      "dark-M"
    case .darkAccessibility3:
      "dark-AX3"
    }
  }
}

@MainActor
enum MoruUITestSupport {
  static let appBundleIdentifier = "com.teammoru.Moru"
  static let clockMillis = "1784325600000"
  static let locale = "ko-KR"
  static let timeZone = "Asia/Seoul"

  static func launch(
    fixture: MoruLedgerFixture,
    variant: MoruLedgerVariant
  ) -> XCUIApplication {
    let app = XCUIApplication(bundleIdentifier: appBundleIdentifier)
    app.launchArguments = launchArguments(fixture: fixture, variant: variant)
    app.launch()
    return app
  }

  static func attachment(
    for fixture: MoruLedgerFixture,
    variant: MoruLedgerVariant,
    app: XCUIApplication
  ) -> XCTAttachment {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = baselineReference(for: fixture, variant: variant)
    attachment.lifetime = .keepAlways
    return attachment
  }

  static func baselineReference(
    for fixture: MoruLedgerFixture,
    variant: MoruLedgerVariant
  ) -> String {
    "Moru/MoruUITests/Baselines/iPhone16-iOS26/ko-KR-Asia-Seoul/"
      + "\(variant.baselineName)/\(fixture.rawValue).png"
  }

  private static func launchArguments(
    fixture: MoruLedgerFixture,
    variant: MoruLedgerVariant
  ) -> [String] {
    [
      "-AppleLanguages", "(ko-KR)",
      "-AppleLocale", "ko_KR",
      "-AppleCalendar", "gregorian",
      "-AppleTimeZone", timeZone,
      "-AppleInterfaceStyle", variant.interfaceStyle,
      "-UIPreferredContentSizeCategoryName", variant.contentSizeCategory,
      "-moruUITestFixture", fixture.rawValue,
      "-moruUITestClockMillis", clockMillis,
      "-moruUITestLocale", locale,
      "-moruUITestTimeZone", timeZone,
      "-moruUITestDisableAnimations"
    ]
  }

}
