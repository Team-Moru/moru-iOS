import XCTest

@MainActor
final class MoruReviewWeatherUITests: XCTestCase {
  private enum LocationAuthorizationFixture: Equatable {
    case authorized
    case denied
  }

  private let app = XCUIApplication()

  func testAccountConnectionShowsRoundSocialLoginButtons() {
    launchApp(locationAuthorization: .denied)

    let profileTab = app.buttons["app.tab.my"]
    XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
    profileTab.tap()

    let accountCard = app.buttons["profile.account.card"]
    XCTAssertTrue(accountCard.waitForExistence(timeout: 5))
    accountCard.tap()

    let roundSocialLoginButtons = [
      app.buttons["profile.account.google-sign-in"],
      app.buttons["profile.account.kakao-sign-in"],
    ]
    for button in roundSocialLoginButtons {
      XCTAssertTrue(button.waitForExistence(timeout: 5))
      XCTAssertEqual(button.frame.width, button.frame.height, accuracy: 0.5)
      XCTAssertGreaterThan(button.frame.width, 50)
    }

    let appleButton = app.buttons["profile.account.apple-sign-in"]
    XCTAssertTrue(appleButton.waitForExistence(timeout: 5))
    XCTAssertGreaterThan(appleButton.frame.height, 50)

    attachCurrentUI(named: "profile-account-connection-social-icons")
  }

  private func launchApp(
    locationAuthorization: LocationAuthorizationFixture
  ) {
    continueAfterFailure = false
    app.launchArguments = [
      "-ui-testing-weather-fixture",
      locationAuthorization == .authorized
        ? "-ui-testing-weather-location-authorized"
        : "-ui-testing-weather-location-denied",
    ]
    app.launch()
    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 10),
      "MORU가 foreground로 실행되어야 합니다."
    )
  }

  func testAuthorizedLocationDisplaysLiveWeather() {
    launchApp(locationAuthorization: .authorized)
    attachCurrentUI(named: "launch")
    assertLiveWeatherAppears()
  }

  func testDeniedLocationOffersSettingsRecovery() {
    launchApp(locationAuthorization: .denied)
    attachCurrentUI(named: "launch")

    let settingsButton = element(
      matching: "설정에서 위치 권한 켜기",
      in: app.buttons
    )
    XCTAssertTrue(
      settingsButton.waitForExistence(timeout: 5),
      "위치 거부 상태에서 설정 이동 버튼이 표시되어야 합니다."
    )
    scrollToMakeHittable(settingsButton)
    settingsButton.tap()

    XCTAssertTrue(
      XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        .wait(for: .runningForeground, timeout: 10),
        "위치 권한 복구 버튼은 MORU의 iOS 설정 화면을 열어야 합니다."
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
    XCTAssertLessThan(
      attributionMark.frame.midY,
      weatherReading.frame.midY,
      "Apple Weather 마크가 날씨 값의 오른쪽 위에 있어야 합니다."
    )
    XCTAssertGreaterThanOrEqual(
      attributionMark.frame.minX,
      weatherCard.frame.minX,
      "Apple Weather 마크가 날씨 카드의 왼쪽 경계를 벗어나면 안 됩니다."
    )
    XCTAssertGreaterThanOrEqual(
      attributionMark.frame.minY,
      weatherCard.frame.minY,
      "Apple Weather 마크가 날씨 카드의 위쪽 경계를 벗어나면 안 됩니다."
    )
    XCTAssertLessThanOrEqual(
      attributionMark.frame.maxX,
      weatherCard.frame.maxX,
      "Apple Weather 마크가 날씨 카드의 오른쪽 경계를 벗어나면 안 됩니다."
    )
    XCTAssertLessThanOrEqual(
      attributionMark.frame.maxY,
      weatherCard.frame.maxY,
      "Apple Weather 마크가 날씨 카드의 아래쪽 경계를 벗어나면 안 됩니다."
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

}
