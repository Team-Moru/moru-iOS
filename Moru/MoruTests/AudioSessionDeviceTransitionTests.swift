//
//  AudioSessionDeviceTransitionTests.swift
//  MoruTests
//

import AVFoundation
import XCTest
@testable import Moru

/// 실기기에서만 의미가 있는 오디오 세션 측정.
///
/// `AudioSessionOwnershipTests`는 스파이로 "누가 무엇을 언제 부르는가"를 고정한다.
/// 스파이는 항상 성공하므로, 진짜 세션에서만 드러나는 두 가지를 여기서 잰다.
///
/// 1. 재생 → 녹음 왕복이 실제로 성공하는가. 마이크 권한이 없으면 `.playAndRecord`
///    활성화는 실기기에서 던진다. 스파이는 이걸 감춘다.
/// 2. 왕복이 얼마나 걸리는가. 첫 음절 잘림을 "세션 전환이 느려서"로 설명하려면
///    그 느림에 숫자가 있어야 한다.
///
/// 시뮬레이터는 오디오 하드웨어가 없어 숫자가 의미 없으므로 건너뛴다.
/// 스모크 플랜에는 넣지 않고 실기기에서 `-only-testing`으로 돌린다.
@MainActor
final class AudioSessionDeviceTransitionTests: XCTestCase {
  override func setUpWithError() throws {
    #if targetEnvironment(simulator)
      throw XCTSkip("실기기 전용 측정입니다. 시뮬레이터에는 오디오 하드웨어가 없습니다.")
    #endif
  }

  override func tearDown() async throws {
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )
  }

  /// 안내 재생이 쓰는 `.playback` 활성화 비용.
  func testPlaybackActivationCost() throws {
    let session = AVAudioSession.sharedInstance()
    let recorder = TransitionRecorder(session: session)

    try recorder.measure("setCategory(.playback)") {
      try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }
    try recorder.measure("setActive(true)") {
      try session.setActive(true)
    }
    try recorder.measure("setActive(false)") {
      try session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    recorder.report(name: "재생 세션 확보/해제")
    XCTAssertEqual(session.category, .playback)
  }

  /// `RoutineAudioSessionCoordinator.activateForSpeechInput`가 진짜 세션에 거는
  /// 왕복 그대로. 이 왕복이 한 단계 안에서 반복되면 그만큼 재생이 끊긴다.
  func testSpeechInputRoundTripCostAndOutcome() throws {
    let session = AVAudioSession.sharedInstance()
    let recorder = TransitionRecorder(session: session)

    // 안내가 재생 중인 상태에서 출발한다.
    try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    try session.setActive(true)

    try recorder.measure("setActive(false)") {
      try session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    var activationError: Error?
    try recorder.measure("setCategory(.playAndRecord)") {
      try session.setCategory(
        .playAndRecord,
        mode: .spokenAudio,
        options: [.allowBluetoothHFP, .defaultToSpeaker]
      )
    }
    do {
      try recorder.measure("setActive(true)") {
        try session.setActive(true)
      }
    } catch {
      activationError = error
    }

    recorder.report(name: "재생 → 녹음 왕복")

    if let activationError {
      // 실패 자체가 결과다. 권한이 없으면 단계 중간에 음성 입력이 통째로
      // 죽고, 지금 코드는 안내 재생만 되살린 뒤 조용히 넘어간다.
      XCTFail(
        """
        녹음 세션 활성화가 실기기에서 실패했습니다: \(activationError)
        마이크 권한 상태: \(AVAudioApplication.shared.recordPermission)
        """
      )
      return
    }

    XCTAssertEqual(session.category, .playAndRecord)
  }

  /// 지금 코드는 카테고리를 바꾸기 전에 세션을 껐다가 다시 켠다. 끄지 않고
  /// 카테고리만 바꾸면 얼마나 아끼는지 잰다. 이 차이가 "단일 소유자" 작업의
  /// 실제 값어치다.
  func testCategorySwitchWithoutDeactivationCost() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    try session.setActive(true)

    let recorder = TransitionRecorder(session: session)
    try recorder.measure("setCategory(.playAndRecord) 활성 상태에서") {
      try session.setCategory(
        .playAndRecord,
        mode: .spokenAudio,
        options: [.allowBluetoothHFP, .defaultToSpeaker]
      )
    }
    try recorder.measure("setCategory(.playback) 되돌리기") {
      try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    recorder.report(name: "끄지 않고 카테고리만 전환")

    // 끄지 않고 바꿔도 세션은 살아 있어야 한다. 살아 있지 않다면 이 경로는
    // 애초에 대안이 아니다.
    XCTAssertEqual(session.category, .playback)
    XCTAssertFalse(session.currentRoute.outputs.isEmpty)
  }
}

/// 전환 한 건씩 벽시계로 재고, 끝나면 한 줄로 찍는다.
@MainActor
private final class TransitionRecorder {
  private let session: AVAudioSession
  private var samples: [(label: String, milliseconds: Double)] = []

  init(session: AVAudioSession) {
    self.session = session
  }

  func measure(_ label: String, _ body: () throws -> Void) throws {
    let start = DispatchTime.now().uptimeNanoseconds
    defer {
      let elapsed = DispatchTime.now().uptimeNanoseconds - start
      samples.append((label, Double(elapsed) / 1_000_000))
    }
    try body()
  }

  func report(name: String) {
    let total = samples.reduce(0) { $0 + $1.milliseconds }
    let detail = samples
      .map { String(format: "%@ %.1fms", $0.label, $0.milliseconds) }
      .joined(separator: " → ")
    print(
      String(
        format: "[오디오세션] %@: 합계 %.1fms | %@ | 경로 %@",
        name,
        total,
        detail,
        session.currentRoute.outputs.first?.portType.rawValue ?? "없음"
      )
    )
  }
}
