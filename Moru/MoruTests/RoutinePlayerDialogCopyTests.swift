//
//  RoutinePlayerDialogCopyTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

final class RoutinePlayerDialogCopyTests: XCTestCase {
  func testEndAndCloseDialogsAskDifferentQuestions() {
    let end = RoutinePlayerDialogCopy.exit(.endedEarly)
    let close = RoutinePlayerDialogCopy.exit(.userDismissed)

    XCTAssertEqual(end, .endRoutine)
    XCTAssertEqual(close, .closeRoutine)
    XCTAssertEqual(end.title, "루틴을 종료할까요?")
    XCTAssertEqual(close.title, "루틴을 닫을까요?")
    XCTAssertNotEqual(end.message, close.message)
    XCTAssertNotEqual(end.confirmTitle, close.confirmTitle)
    XCTAssertEqual(end.cancelTitle, "계속하기")
    XCTAssertEqual(close.cancelTitle, "계속하기")
  }

  func testEndDialogKeepsTheOriginalRecordingPromise() {
    XCTAssertEqual(
      RoutinePlayerDialogCopy.endRoutine.message,
      "지금까지 완료한 항목만 저장돼요.\n나머지는 미완료로 기록됩니다."
    )
    XCTAssertEqual(RoutinePlayerDialogCopy.endRoutine.confirmTitle, "종료하기")
  }

  func testCloseDialogExplainsRecordAndHomeReturn() {
    XCTAssertEqual(
      RoutinePlayerDialogCopy.closeRoutine.message,
      "지금까지의 진행은 기록에 남고\n홈으로 돌아가요."
    )
    XCTAssertEqual(RoutinePlayerDialogCopy.closeRoutine.confirmTitle, "닫기")
  }

  func testSkipDialogCopyIsUnchanged() {
    XCTAssertEqual(RoutinePlayerDialogCopy.skipStep.title, "이 항목을 건너뛸까요?")
    XCTAssertEqual(
      RoutinePlayerDialogCopy.skipStep.message,
      "건너뛰면 현재 루틴은 미완료로 기록돼요.\n다음 루틴으로 넘어갈게요."
    )
    XCTAssertEqual(RoutinePlayerDialogCopy.skipStep.confirmTitle, "건너뛰기")
  }

  func testDiscardDialogOffersRetryBeforeLeaving() {
    let copy = RoutinePlayerDialogCopy.discardUnsavedRun
    XCTAssertEqual(copy.title, "기록 없이 나갈까요?")
    XCTAssertEqual(
      copy.message,
      "저장하지 못한 오늘 기록은 남지 않아요.\n다시 시도하면 저장할 수 있어요."
    )
    XCTAssertEqual(copy.cancelTitle, "돌아가기")
    XCTAssertEqual(copy.confirmTitle, "기록 없이 나가기")
  }
}
