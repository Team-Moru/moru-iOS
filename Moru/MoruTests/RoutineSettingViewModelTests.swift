//
//  RoutineSettingViewModelTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

final class RoutineSettingViewModelTests: XCTestCase {
  @MainActor
  func testLoadBuildsFigmaRoutineListMetadata() {
    let viewModel = RoutineSettingViewModel(dependencies: .homePreview)

    viewModel.load()

    XCTAssertEqual(viewModel.state.routines.map(\.title), [
      "활력 루틴",
      "주말 루틴",
      "명상 루틴",
    ])
    XCTAssertEqual(viewModel.state.routines.map(\.stepCountText), [
      "6개 항목",
      "3개 항목",
      "3개 항목",
    ])
    XCTAssertEqual(viewModel.state.routines.map(\.estimatedDurationText), [
      "15분",
      "8분",
      "8분",
    ])
    XCTAssertEqual(viewModel.state.routines.map(\.isActive), [
      true,
      false,
      false,
    ])
  }

  @MainActor
  func testActivationChangePersistsAndReloadsRoutineState() throws {
    let viewModel = RoutineSettingViewModel(dependencies: .homePreview)
    viewModel.load()
    let routineID = try XCTUnwrap(viewModel.state.routines.first?.id)

    XCTAssertTrue(
      viewModel.routineActivationDidChange(id: routineID, isActive: false)
    )

    XCTAssertFalse(
      try XCTUnwrap(viewModel.state.routines.first { $0.id == routineID }).isActive
    )
  }

  @MainActor
  func testEditAndAddActionsBuildExpectedDrafts() throws {
    let viewModel = RoutineSettingViewModel(dependencies: .homePreview)
    viewModel.load()
    let weekendRoutine = try XCTUnwrap(
      viewModel.state.routines.first { $0.title == "주말 루틴" }
    )

    let editDraft = try XCTUnwrap(viewModel.makeDraft(for: weekendRoutine.id))
    let newDraft = viewModel.makeNewDraft()

    XCTAssertEqual(editDraft.routineID, weekendRoutine.id)
    XCTAssertEqual(editDraft.title, "주말 루틴")
    XCTAssertEqual(editDraft.steps.count, 3)
    XCTAssertEqual(newDraft.title, "새 루틴")
    XCTAssertNil(newDraft.routineID)
  }
}
