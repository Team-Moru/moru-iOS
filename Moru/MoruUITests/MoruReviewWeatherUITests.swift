import XCTest

@MainActor
final class MoruReviewWeatherUITests: XCTestCase {
  private let app = XCUIApplication()

  private func launchApp() {
    continueAfterFailure = false
    app.launchArguments = ["-ui-testing-weather-fixture"]
    app.launch()
    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 10),
      "MORU가 foreground로 실행되어야 합니다."
    )
  }

  func testFreshLocationPermissionDisplaysLiveWeather() {
    installLocationAllowMonitor()
    launchApp()
    attachCurrentUI(named: "launch")

    let refreshButton = element(
      matching: "현재 위치 날씨 새로고침",
      in: app.buttons
    )
    if !refreshButton.waitForExistence(timeout: 2) {
      triggerPendingLocationPrompt()
    }
    assertLiveWeatherAppears()
  }

  private func installLocationAllowMonitor() {
    addUIInterruptionMonitor(withDescription: "Core Location allow") { alert in
      let labels = ["앱을 사용하는 동안 허용", "Allow While Using App"]
      for label in labels {
        let button = alert.descendants(matching: .button)
          .matching(NSPredicate(format: "label CONTAINS %@", label))
          .firstMatch
        if button.exists {
          button.tap()
          return true
        }
      }
      return false
    }
  }

  func testDeniedLocationCanBeEnabledInSettingsAndAutomaticallyRetries() {
    launchApp()
    attachCurrentUI(named: "launch")

    let settingsButton = element(
      matching: "설정에서 위치 권한 켜기",
      in: app.buttons
    )
    if !settingsButton.waitForExistence(timeout: 2) {
      triggerPendingLocationPrompt()
    }

    XCTAssertTrue(
      settingsButton.waitForExistence(timeout: 5),
      "위치 거부 상태에서 설정 이동 버튼이 표시되어야 합니다."
    )
    scrollToMakeHittable(settingsButton)
    settingsButton.tap()

    enableLocationInSettings()
    app.activate()

    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 10),
      "Settings에서 돌아온 뒤 MORU가 foreground여야 합니다."
    )
    assertLiveWeatherAppears()
  }

  private func triggerPendingLocationPrompt() {
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
  }

  private func enableLocationInSettings() {
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    XCTAssertTrue(
      settings.wait(for: .runningForeground, timeout: 10),
      "MORU 설정 화면이 열려야 합니다."
    )
    attachCurrentUI(named: "settings-app-detail", application: settings)

    let locationRow = findLocationRow(in: settings)
    XCTAssertNotNil(locationRow, "MORU 설정 화면에 위치 항목이 있어야 합니다.")
    locationRow?.tap()
    attachCurrentUI(named: "settings-location-detail", application: settings)

    let whileUsing = firstExistingElement(
      in: settings.descendants(matching: .any),
      labels: [
        "앱을 사용하는 동안",
        "While Using the App",
      ],
      timeout: 8
    )
    XCTAssertNotNil(
      whileUsing,
      "위치 설정 화면에 앱 사용 중 허용 옵션이 있어야 합니다."
    )
    whileUsing?.tap()
  }

  private func findLocationRow(in settings: XCUIApplication) -> XCUIElement? {
    let allElements = settings.descendants(matching: .any)
    if let locationRow = firstExistingElement(
      in: allElements,
      labels: ["위치", "Location"],
      timeout: 3
    ) {
      return locationRow
    }

    let appSearch = firstExistingElement(
      in: settings.searchFields,
      labels: ["앱 검색", "Search Apps", "검색", "Search"],
      timeout: 5
    )
    XCTAssertNotNil(
      appSearch,
      "앱별 설정 화면으로 바로 이동하지 않으면 앱 검색 필드가 있어야 합니다."
    )
    appSearch?.tap()
    appSearch?.typeText("Moru")
    attachCurrentUI(named: "settings-app-search", application: settings)

    let moruResult = firstExistingExactElement(
      in: settings.staticTexts,
      labels: ["Moru", "모루"],
      timeout: 5
    )
    XCTAssertNotNil(moruResult, "설정 앱 검색 결과에 MORU가 표시되어야 합니다.")
    moruResult?.tap()
    attachCurrentUI(named: "settings-moru-detail", application: settings)

    return firstExistingElement(
      in: settings.descendants(matching: .any),
      labels: ["위치", "Location"],
      timeout: 8
    )
  }

  private func assertLiveWeatherAppears() {
    let refreshButton = element(
      matching: "현재 위치 날씨 새로고침",
      in: app.buttons
    )
    XCTAssertTrue(
      refreshButton.waitForExistence(timeout: 30),
      "권한 허용 후 30초 안에 실시간 날씨가 표시되어야 합니다."
    )

    let attributionMark = app.descendants(matching: .any)
      .matching(identifier: "home.weather.attribution.mark")
      .firstMatch
    let weatherCard = app.descendants(matching: .any)
      .matching(identifier: "home.weather.card")
      .firstMatch
    let weatherReading = app.descendants(matching: .any)
      .matching(identifier: "home.weather.reading")
      .firstMatch
    XCTAssertTrue(
      attributionMark.waitForExistence(timeout: 5),
      "날씨 값과 함께 클릭 가능한 Apple Weather 마크가 표시되어야 합니다."
    )
    XCTAssertTrue(
      weatherCard.waitForExistence(timeout: 5)
        && weatherReading.waitForExistence(timeout: 5),
      "Apple Weather 마크 위치를 검증할 날씨 카드와 날씨 값이 표시되어야 합니다."
    )

    scrollAttributionIntoRecordingViewport(
      attributionMark: attributionMark,
      weatherCard: weatherCard,
      weatherReading: weatherReading
    )
    attachCurrentUI(named: "weather-with-attribution")
  }

  private func scrollAttributionIntoRecordingViewport(
    attributionMark: XCUIElement,
    weatherCard: XCUIElement,
    weatherReading: XCUIElement
  ) {
    let scrollView = app.scrollViews.firstMatch
    XCTAssertTrue(scrollView.exists, "홈의 스크롤 영역이 존재해야 합니다.")

    for _ in 0..<4 where attributionMark.frame.midY > scrollView.frame.midY {
      let start = scrollView.coordinate(
        withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)
      )
      let end = scrollView.coordinate(
        withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)
      )
      start.press(forDuration: 0.05, thenDragTo: end)
    }

    XCTAssertLessThanOrEqual(
      attributionMark.frame.midY,
      scrollView.frame.midY,
      "Apple Weather 마크가 녹화 화면의 위쪽 절반에 보여야 합니다."
    )
    XCTAssertTrue(
      attributionMark.isHittable,
      "Apple Weather 마크가 법적 출처 페이지 링크로 탭 가능해야 합니다."
    )
    XCTAssertGreaterThan(
      attributionMark.frame.midX,
      weatherCard.frame.midX,
      "Apple Weather 마크가 날씨 카드 오른쪽에 있어야 합니다."
    )
    XCTAssertGreaterThan(
      attributionMark.frame.midY,
      weatherReading.frame.midY,
      "Apple Weather 마크가 날씨 값보다 아래에 있어야 합니다."
    )
    XCTAssertLessThanOrEqual(
      weatherCard.frame.maxX - attributionMark.frame.maxX,
      44,
      "Apple Weather 마크가 날씨 카드 오른쪽 하단 여백에 맞아야 합니다."
    )
    XCTAssertLessThanOrEqual(
      weatherCard.frame.maxY - attributionMark.frame.maxY,
      24,
      "Apple Weather 마크가 날씨 카드 하단 여백에 맞아야 합니다."
    )
  }

  private func scrollToMakeHittable(_ element: XCUIElement) {
    let scrollView = app.scrollViews.firstMatch

    for _ in 0..<4 where !element.isHittable {
      if scrollView.exists {
        let start = scrollView.coordinate(
          withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)
        )
        let end = scrollView.coordinate(
          withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52)
        )
        start.press(forDuration: 0.05, thenDragTo: end)
      } else {
        app.swipeUp()
      }
    }

    attachCurrentUI(named: "after-weather-scroll")
    XCTAssertTrue(
      element.waitForExistence(timeout: 5) && element.isHittable,
      "\(element) 요소가 스크롤 후 탭 가능해야 합니다."
    )
  }

  private func attachCurrentUI(
    named name: String,
    application: XCUIApplication? = nil
  ) {
    let target = application ?? app
    let hierarchy = XCTAttachment(
      data: Data(target.debugDescription.utf8),
      uniformTypeIdentifier: "public.plain-text"
    )
    hierarchy.name = "\(name)-hierarchy"
    hierarchy.lifetime = .keepAlways
    add(hierarchy)

    let screenshot = XCTAttachment(screenshot: target.screenshot())
    screenshot.name = "\(name)-screenshot"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  private func element(
    matching label: String,
    in query: XCUIElementQuery
  ) -> XCUIElement {
    query.matching(
      NSPredicate(format: "label CONTAINS %@", label)
    ).firstMatch
  }

  private func firstExistingElement(
    in query: XCUIElementQuery,
    labels: [String],
    timeout: TimeInterval
  ) -> XCUIElement? {
    let deadline = Date().addingTimeInterval(timeout)

    repeat {
      for label in labels {
        let candidate = query.matching(
          NSPredicate(format: "label CONTAINS %@", label)
        ).firstMatch
        if candidate.exists {
          return candidate
        }
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline

    return nil
  }

  private func firstExistingExactElement(
    in query: XCUIElementQuery,
    labels: [String],
    timeout: TimeInterval
  ) -> XCUIElement? {
    let deadline = Date().addingTimeInterval(timeout)

    repeat {
      for label in labels {
        let candidate = query.matching(
          NSPredicate(format: "label == %@", label)
        ).firstMatch
        if candidate.exists {
          return candidate
        }
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline

    return nil
  }
}
