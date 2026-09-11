//
//  AudioSessionOwnershipTests.swift
//  MoruTests
//

import AVFoundation
import XCTest
@testable import Moru

/// 오디오 세션을 하나의 소유자로 모으기 전에, 지금 누가 언제 무엇을 호출하는지
/// 먼저 고정한다. 소유자 전환 뒤에도 재생·녹음 전환의 겉보기 순서는 같아야 한다.
@MainActor
final class AudioSessionOwnershipTests: XCTestCase {
  func testSpeechInputActivationStopsGuidanceAndSwitchesToPlayAndRecord() async throws {
    let session = AudioSessionSpy()
    let guidance = GuidancePlaybackSpy()
    let coordinator = RoutineAudioSessionCoordinator(
      guidancePlayback: guidance,
      audioSession: session
    )

    try await coordinator.activateForSpeechInput()

    // 안내 재생을 먼저 멈춘 뒤에 카테고리를 바꾼다. 순서가 뒤집히면
    // 녹음 세션이 재생 중인 큐를 잘라 첫 음절이 사라진다.
    XCTAssertEqual(guidance.stopAndWaitCallCount, 1)
    XCTAssertEqual(
      session.events,
      [
        .setActive(false),
        .setCategory(.playAndRecord, mode: .spokenAudio),
        .setActive(true),
      ]
    )
  }

  func testSpeechInputDeactivationReleasesTheSessionAndResumesGuidance() async throws {
    let session = AudioSessionSpy()
    let guidance = GuidancePlaybackSpy()
    let coordinator = RoutineAudioSessionCoordinator(
      guidancePlayback: guidance,
      audioSession: session
    )

    try await coordinator.activateForSpeechInput()
    session.events.removeAll()
    coordinator.deactivateSpeechInput()

    XCTAssertEqual(session.events, [.setActive(false)])
    XCTAssertEqual(guidance.resumeCallCount, 1)
  }

  func testFailedActivationLeavesTheSessionReleasedAndResumesGuidance() async {
    let session = AudioSessionSpy()
    session.setCategoryError = AudioSessionSpyError.denied
    let guidance = GuidancePlaybackSpy()
    let coordinator = RoutineAudioSessionCoordinator(
      guidancePlayback: guidance,
      audioSession: session
    )

    do {
      try await coordinator.activateForSpeechInput()
      XCTFail("Activation should rethrow the session error.")
    } catch {
      XCTAssertTrue(error is AudioSessionSpyError)
    }

    XCTAssertEqual(session.events.last, .setActive(false))
    XCTAssertEqual(guidance.resumeCallCount, 1)
  }

  func testLocalPlayerDoesNotDeactivateASessionItNeverActivated() async {
    let session = AudioSessionSpy()
    let player = LocalFileRoutineAudioPlayer(
      playbackState: RoutineGuidancePlaybackState(),
      audioSession: session
    )

    // 재생한 적이 없으니 끌 세션도 없다. 예전에는 무조건 껐고, 그러면 번들
    // 안내나 프로필 미리듣기가 잡고 있던 세션이 이 호출 하나로 내려갔다.
    player.stop()

    XCTAssertTrue(session.events.isEmpty)
  }

  func testLocalPlayerReleasesTheSessionExactlyAsOftenAsItTakesIt() async {
    let session = AudioSessionSpy()
    let player = LocalFileRoutineAudioPlayer(
      playbackState: RoutineGuidancePlaybackState(),
      audioSession: session
    )

    let result = await player.playLocalAudioSequence([
      URL(fileURLWithPath: "/tmp/moru-missing-audio.m4a"),
    ])

    XCTAssertEqual(result, .failedToStart)
    let activations = session.events.filter { $0 == .setActive(true) }.count
    let deactivations = session.events.filter { $0 == .setActive(false) }.count
    XCTAssertEqual(activations, deactivations)

    // 이미 놓은 세션을 다시 끄지 않는다. 예전에는 이 호출이 다른 재생기가 잡고
    // 있던 세션을 내려 버렸다.
    session.events.removeAll()
    player.stop()

    XCTAssertTrue(session.events.isEmpty)
  }

  func testDeactivationWithoutActivationDoesNotTouchTheSession() {
    let session = AudioSessionSpy()
    let coordinator = RoutineAudioSessionCoordinator(
      guidancePlayback: GuidancePlaybackSpy(),
      audioSession: session
    )

    coordinator.deactivateSpeechInput()

    XCTAssertTrue(session.events.isEmpty)
  }
}

private enum AudioSessionSpyError: Error {
  case denied
}

private enum AudioSessionEvent: Equatable {
  case setCategory(AVAudioSession.Category, mode: AVAudioSession.Mode)
  case setActive(Bool)
}

@MainActor
private final class AudioSessionSpy: AudioSessionControlling {
  var events: [AudioSessionEvent] = []
  var setCategoryError: Error?

  func setCategory(
    _ category: AVAudioSession.Category,
    mode: AVAudioSession.Mode,
    options: AVAudioSession.CategoryOptions
  ) throws {
    if let setCategoryError {
      throw setCategoryError
    }

    events.append(.setCategory(category, mode: mode))
  }

  func setActive(
    _ active: Bool,
    options: AVAudioSession.SetActiveOptions
  ) throws {
    events.append(.setActive(active))
  }
}

@MainActor
private final class GuidancePlaybackSpy: GuidancePlaybackControlling {
  private(set) var stopAndWaitCallCount = 0
  private(set) var resumeCallCount = 0

  func stopAndWaitUntilIdle() async {
    stopAndWaitCallCount += 1
  }

  func resumeAfterSpeechInput() {
    resumeCallCount += 1
  }
}
