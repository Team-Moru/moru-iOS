//
//  RoutinePresetResourceTests.swift
//  MoruTests
//

import Foundation
import XCTest
@testable import Moru

@MainActor
final class RoutinePresetResourceTests: XCTestCase {
  func testBundledPresetItemsAreCompleteAndUnique() throws {
    let items = try RoutinePresetLoader().loadItems()

    XCTAssertEqual(items.count, 39)
    XCTAssertEqual(Set(items.map(\.id)).count, 39)
    XCTAssertEqual(
      Set(items.map(\.goal)),
      ["활력", "건강", "마음 안정", "습관 형성"]
    )
    XCTAssertTrue(items.allSatisfy { $0.estimatedSeconds > 0 })
  }

  func testBundledAudioMappingsReferenceKnownItemsAndExistingFiles() throws {
    let items = try RoutinePresetLoader().loadItems()
    let loader = RoutineAudioResourceLoader()
    let cues = try loader.loadCues()
    let itemIDs = Set(items.map(\.id))

    XCTAssertEqual(cues.count, 468)
    XCTAssertEqual(Set(cues.map(\.relativePath)).count, 360)
    XCTAssertTrue(cues.allSatisfy { itemIDs.contains($0.itemID) })
    XCTAssertTrue(cues.allSatisfy { loader.resourceURL(for: $0) != nil })
  }

  func testAudioCueLookupUsesItemVoiceAndKind() throws {
    let loader = RoutineAudioResourceLoader()
    let cue = try XCTUnwrap(
      loader.cue(itemID: "HABIT-08", voiceCode: "Aoede", kind: .intro)
    )

    XCTAssertEqual(cue.voiceName, "민서")
    XCTAssertEqual(cue.relativePath, "audio/item_0001/item_0001_Aoede_intro.mp3")
    XCTAssertNotNil(loader.resourceURL(for: cue))
  }

  func testPresetLoaderRejectsUnknownStepType() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let csv = "목표,항목명,유형,항목ID,유형코드,시간(분),시간(초),공통항목,비고\n활력,테스트,확인형,TEST-01,UNKNOWN,1,60,N,"
    try csv.write(
      to: directory.appendingPathComponent("recommended-items.csv"),
      atomically: true,
      encoding: .utf8
    )

    XCTAssertThrowsError(try RoutinePresetLoader(resourceDirectory: directory).loadItems()) {
      XCTAssertEqual(
        $0 as? RoutinePresetLoaderError,
        .invalidStepType("UNKNOWN", row: 2)
      )
    }
  }
}
