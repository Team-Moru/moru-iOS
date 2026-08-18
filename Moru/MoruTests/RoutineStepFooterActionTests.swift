//
//  RoutineStepFooterActionTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

@MainActor
final class RoutineStepFooterActionTests: XCTestCase {
  func testRoutineStepsExposeOnlyTheSkipFooterAction() {
    XCTAssertEqual(RoutineStepFooterAction.allCases, [.skip])
    XCTAssertEqual(RoutineStepFooterAction.skip.title, "건너뛰기")
  }
}
