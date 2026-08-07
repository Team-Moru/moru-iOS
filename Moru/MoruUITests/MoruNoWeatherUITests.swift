import XCTest

@MainActor
final class MoruNoWeatherUITests: XCTestCase {
  func testLaunchDoesNotExposeRemovedWeatherFeature() {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 10),
      "MORU가 foreground로 실행되어야 합니다."
    )

    let removedWeatherLabels = [
      "현재 위치 날씨",
      "현재 위치 날씨 보기",
      "현재 위치 날씨 새로고침",
      "설정에서 위치 권한 켜기",
      "Apple Weather",
      " Weather",
    ]
    let allElements = app.descendants(matching: .any)

    for label in removedWeatherLabels {
      let removedElement = allElements.matching(
        NSPredicate(format: "label CONTAINS %@", label)
      ).firstMatch
      XCTAssertFalse(
        removedElement.exists,
        "제거된 날씨 UI가 앱 화면에 남아 있으면 안 됩니다: \(label)"
      )
    }
  }
}
