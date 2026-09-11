//
//  RoutineStepCompletionMatcherTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

@MainActor
final class RoutineStepCompletionMatcherTests: XCTestCase {
  private let waterStep = RoutineStep(
    type: .input,
    title: "물 한잔 마시기",
    instruction: "물을 마신 뒤 말해주세요.",
    order: 0
  )

  func testWaterDrinkingCompletionAcceptsCompletedAction() {
    let transcripts = ["물 한잔 마셨어", "물을 마셨어요", "물 다 마셨다"]

    XCTAssertTrue(
      transcripts.allSatisfy { transcript in
        RoutineStepCompletionMatcher.isCompleted(transcript, for: waterStep)
      }
    )
  }

  func testClassifiesExplicitCompletionCommand() {
    XCTAssertEqual(
      RoutineStepCompletionMatcher.match("완료했어", for: waterStep),
      .explicit
    )
    XCTAssertEqual(
      RoutineStepCompletionMatcher.match("다음", for: waterStep),
      .explicit
    )
    XCTAssertTrue(
      RoutineStepCompletionMatcher.isCompleted("다음.", for: waterStep)
    )
  }

  func testClassifiesWeakCompletedActionPhrases() {
    let transcripts = [
      "잠자리 정리했어",
      "잠자리 정리했어요",
      "잠자리 정리했다",
      "잠자리 정리 마쳤어",
      "잠자리 정리 끝냈다"
    ]

    XCTAssertTrue(
      transcripts.allSatisfy { transcript in
        RoutineStepCompletionMatcher.match(transcript, for: waterStep) == .weak
      }
    )
  }

  func testClassifiesWaterDrinkingCompletionAsContextual() {
    XCTAssertEqual(
      RoutineStepCompletionMatcher.match("물 한잔 마셨어", for: waterStep),
      .contextual
    )
  }

  func testWaterDrinkingCompletionRejectsNegativeResponse() {
    let transcripts = [
      "물 안 마셨어",
      "잠자리 정리 안 마쳤어",
      "아직 안 됐어",
      "못 끝냈어"
    ]

    XCTAssertTrue(
      transcripts.allSatisfy { transcript in
        RoutineStepCompletionMatcher.match(transcript, for: waterStep) == .none
      }
    )
  }

  func testWaterDrinkingCompletionDoesNotApplyToOtherSteps() {
    let otherStep = RoutineStep(type: .input, title: "스트레칭", order: 0)

    XCTAssertFalse(
      RoutineStepCompletionMatcher.isCompleted("물 한잔 마셨어", for: otherStep)
    )
  }

  // MARK: - 과거형 답변

  func testPastTenseAnswerAboutThisStepsActionIsContextual() {
    // 실기기에서 "마셨어"라고 답했는데 "물"이 없어서 넘어가지 않았다.
    let transcripts = ["마셨어", "마셨어요", "다 마셨습니다", "마셨다", "마셨네"]

    for transcript in transcripts {
      XCTAssertEqual(
        RoutineStepCompletionMatcher.match(transcript, for: waterStep),
        .contextual,
        transcript
      )
    }
  }

  func testPastTenseAnswerAboutAnotherActionDoesNotCompleteTheStep() {
    let transcripts = ["씻었어", "읽었어요", "쭉 폈다"]

    for transcript in transcripts {
      XCTAssertEqual(
        RoutineStepCompletionMatcher.match(transcript, for: waterStep),
        .none,
        transcript
      )
    }
  }

  func testEachStepRecognisesItsOwnVerb() {
    let washStep = RoutineStep(
      type: .input,
      title: "세수하기",
      instruction: "얼굴을 씻고 말해주세요.",
      order: 0
    )

    XCTAssertEqual(
      RoutineStepCompletionMatcher.match("씻었어", for: washStep),
      .contextual
    )
    XCTAssertEqual(
      RoutineStepCompletionMatcher.match("마셨어", for: washStep),
      .none
    )
  }

  func testStativeFutureAndOngoingFormsAreNotCompletedActions() {
    let transcripts = ["물 있어", "마시겠어", "마시는 중", "마실게", "마셔"]

    for transcript in transcripts {
      XCTAssertEqual(
        RoutineStepCompletionMatcher.match(transcript, for: waterStep),
        .none,
        transcript
      )
    }
  }

  func testPastTenseWithNegationParticleIsNotCompleted() {
    let transcripts = ["안 마셨어", "못 마셨어요", "아직 안 마셨다", "물 안 마셨는데"]

    for transcript in transcripts {
      XCTAssertEqual(
        RoutineStepCompletionMatcher.match(transcript, for: waterStep),
        .none,
        transcript
      )
    }
  }

  // MARK: - 활용하며 모음이 바뀌는 동사

  func testContractedVerbsMatchTheirDictionaryFormInTheStepTitle() {
    // 사용자가 만드는 루틴은 제목이 사전형("쓰기")이고 답은 활용형("썼어")이다.
    let cases: [(title: String, answer: String)] = [
      ("일기 쓰기", "썼어"),                 // ㅡ 탈락
      ("불 끄기", "껐어요"),                 // ㅡ 탈락
      ("창문 열고 하늘 보기", "봤어"),        // ㅗ+ㅏ → ㅘ
      ("화분에 물 주기", "줬어"),            // ㅜ+ㅓ → ㅝ
      ("기지개 펴기", "폈다"),               // 그대로
      ("담배 대신 껌 씹기", "씹었어"),        // 규칙 활용
      ("산책 10분 걷기", "걸었어"),          // ㄷ 불규칙 — 받침 무시로 통과
      ("노래 한 곡 부르기", "불렀어"),        // 르 불규칙 — 앞 음절로 통과
    ]

    for (title, answer) in cases {
      let step = RoutineStep(type: .input, title: title, order: 0)
      XCTAssertEqual(
        RoutineStepCompletionMatcher.match(answer, for: step),
        .contextual,
        "\(title) ← \(answer)"
      )
    }
  }

  func testContractedVerbsStillDoNotCrossOverToOtherSteps() {
    let writingStep = RoutineStep(type: .input, title: "일기 쓰기", order: 0)

    for answer in ["봤어", "줬어", "마셨어"] {
      XCTAssertEqual(
        RoutineStepCompletionMatcher.match(answer, for: writingStep),
        .none,
        answer
      )
    }
  }
}
