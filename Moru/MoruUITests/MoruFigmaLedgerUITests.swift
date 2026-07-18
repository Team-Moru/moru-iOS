import XCTest

@MainActor
final class MoruFigmaLedgerUITests: XCTestCase {
  func testFigmaLedgerFixturesAcrossAppearanceAndDynamicType() {
    for fixture in MoruLedgerFixture.allCases {
      XCTAssertFalse(fixture.figmaNodeIDs.isEmpty)
      XCTAssertEqual(fixture.figmaURLs.count, fixture.figmaNodeIDs.count)
      XCTAssertTrue(
        fixture.figmaURLs.allSatisfy {
          $0.hasPrefix("https://www.figma.com/design/vrVBDLEy0UmqlLVfxnUcY9/")
        }
      )
      for variant in MoruLedgerVariant.allCases {
        let app = MoruUITestSupport.launch(fixture: fixture, variant: variant)
        assertLedgerContract(for: fixture, in: app)
        add(MoruUITestSupport.attachment(for: fixture, variant: variant, app: app))
        app.terminate()
      }
    }
  }

  func testDynamicTypeLaunchOverrideAppliesMediumAndAccessibility3() {
    for variant in [MoruLedgerVariant.lightMedium, .lightAccessibility3] {
      let app = MoruUITestSupport.launch(fixture: .profileRoot, variant: variant)
      let profile = element("profile.root", in: app)
      XCTAssertTrue(profile.waitForExistence(timeout: 5))
      XCTAssertEqual(profile.value as? String, variant.dynamicTypeProbeValue)
      app.terminate()
    }
  }

  private func assertLedgerContract(
    for fixture: MoruLedgerFixture,
    in app: XCUIApplication
  ) {
    switch fixture {
    case .launchSlow:
      assertElement("launch.status", label: "루틴을 준비하고 있어요", in: app)
    case .onboardingExperience:
      assertElement(
        "onboarding.experience.title",
        label: "루틴 경험이\n있으신가요?",
        in: app
      )
    case .onboardingCompletion:
      assertElement("onboarding.primary", label: "루틴 체험하기", in: app)
    case .trialStep:
      assertElement("routinePlayer.step.title", label: "오늘의 루틴", in: app)
    case .trialInput:
      assertElement("routinePlayer.step.title", label: "오늘의 루틴", in: app)
      assertElement("routinePlayer.input", label: "오늘의 다짐", in: app)
    case .trialComplete:
      assertElement("routineCompletion.primary", label: "홈으로", in: app)
      XCTAssertFalse(app.buttons["오늘의 기록 확인"].exists)
      XCTAssertFalse(app.descendants(matching: .any)["routineCompletion.home"].exists)
    case .homeWeatherFresh:
      assertElement("home.root", label: "홈", in: app)
      assertIdentifier("app.tabBar", in: app)
      assertElementContaining("home.weather.card", text: "업데이트 07:00", in: app)
    case .profileRoot:
      assertElement("profile.root", label: "마이", in: app)
      assertIdentifier("profile.name", in: app)
      assertIdentifier("profile.alarm.status", in: app)
      assertIdentifier("profile.reset", in: app)
      assertIdentifier("profile.voice.chooser", in: app)
    case .alarmPermissionOff:
      assertElement("profile.alarm.status", label: "알람 권한이 꺼져 있어요", in: app)
    case .voiceSelection:
      let chooser = element("profile.voice.chooser", in: app)
      XCTAssertTrue(chooser.waitForExistence(timeout: 5))
      chooser.tap()
      assertIdentifier("voice.selection.list", in: app)
      assertIdentifier("voice.preview.moru.ko.yuna", in: app)
      assertIdentifier("voice.preview.moru.ko.sora", in: app)
    case .notificationDowngrade:
      assertLabel("현재는 기기 알림으로 알려드려요.", in: app)
      assertNoAlarmLifecycleSurface(in: app)
    case .regularComplete:
      assertElement("routineCompletion.primary", label: "오늘의 기록 확인", in: app)
      assertElement("routineCompletion.home", label: "홈으로", in: app)
    case .historyDashboard:
      assertElementContaining(
        "history.metrics.averageWake",
        text: "평균 기상 시간",
        in: app
      )
      assertIdentifier("history.heatmap", in: app)
    case .historyWeekly:
      let summary = app.buttons.matching(
        NSPredicate(format: "label CONTAINS %@", "이번 주 루틴 리포트")
      ).firstMatch
      XCTAssertTrue(summary.waitForExistence(timeout: 5))
      summary.tap()
      assertElement("history.weekly.root", label: "이번 주 루틴 리포트", in: app)
    case .historyDetail:
      assertElement("history.runDetail", label: "실행 기록", in: app)
    case .componentsDefault:
      assertElement("components.root", label: "MORU 컴포넌트", in: app)
    case .absenceAudit:
      assertElement("profile.root", label: "마이", in: app)
      assertNoV2CommerceOrSocialSurface(in: app)
      assertNoAlarmLifecycleSurface(in: app)
    }
  }

  private func assertIdentifier(
    _ identifier: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(element(identifier, in: app).waitForExistence(timeout: 5),
      "Missing accessibility identifier: \(identifier)", file: file, line: line)
  }

  private func assertElement(
    _ identifier: String,
    label: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let target = element(identifier, in: app)
    XCTAssertTrue(
      target.waitForExistence(timeout: 5),
      "Missing accessibility identifier: \(identifier)",
      file: file,
      line: line
    )
    XCTAssertEqual(
      target.label,
      label,
      "Unexpected copy for: \(identifier)",
      file: file,
      line: line
    )
  }

  private func assertElementContaining(
    _ identifier: String,
    text: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let target = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "identifier == %@ AND label CONTAINS %@",
        identifier,
        text
      )
    ).firstMatch
    XCTAssertTrue(
      target.waitForExistence(timeout: 5),
      "Expected \(identifier) to include: \(text)",
      file: file,
      line: line
    )
  }
  private func assertLabel(
    _ label: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let target = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", label)
    ).firstMatch
    XCTAssertTrue(
      target.waitForExistence(timeout: 5),
      "Missing production copy: \(label)",
      file: file,
      line: line
    )
  }

  private func assertNoAlarmLifecycleSurface(
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    ["알람 종료", "다시 울림", "스누즈", "진동"].forEach { text in
      let target = app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", text)
      ).firstMatch
      XCTAssertFalse(
        target.exists,
        "Unexpected alarm lifecycle surface: \(text)",
        file: file,
        line: line
      )
    }
  }

  private func assertNoV2CommerceOrSocialSurface(
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    ["Google", "Kakao", "Apple로 로그인", "PRO 구매"].forEach { text in
      let target = app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", text)
      ).firstMatch
      XCTAssertFalse(
        target.exists,
        "Unexpected v2 surface: \(text)",
        file: file,
        line: line
      )
    }
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }
}
