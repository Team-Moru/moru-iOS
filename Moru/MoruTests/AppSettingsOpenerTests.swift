//
//  AppSettingsOpenerTests.swift
//  MoruTests
//

import Foundation
import UIKit
import XCTest
@testable import Moru

@MainActor
final class AppSettingsOpenerTests: XCTestCase {
  func testOpenUsesApplicationSettingsURL() async {
    var openedURL: URL?
    let opener = AppSettingsOpener { url in
      openedURL = url
      return true
    }

    let didOpen = await opener.open()

    XCTAssertTrue(didOpen)
    XCTAssertEqual(openedURL?.absoluteString, UIApplication.openSettingsURLString)
  }

  func testOpenReturnsSystemResult() async {
    let opener = AppSettingsOpener { _ in false }

    let didOpen = await opener.open()

    XCTAssertFalse(didOpen)
  }
}
