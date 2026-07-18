//
//  AppleSpeechRecognitionSession.swift
//  Moru
//

import AVFAudio
import Foundation
import Speech

enum AppleSpeechRecognitionSessionError: Error {
  case microphonePermissionDenied
  case localeUnavailable
  case modelDownloadFailed
  case audioSession
  case recognition
}

@MainActor
final class AppleSpeechRecognitionSession: SpeechInputSession {
  private enum Metric {
    static let audioBufferSize: AVAudioFrameCount = 4_096
  }

  var eventHandler: ((SpeechInputSessionEvent) -> Void)?

  private let audioEngine = AVAudioEngine()
  private let audioSessionCoordinator: RoutineAudioSessionCoordinator
  private let locale = Locale(identifier: "ko-KR")
  private var analyzer: SpeechAnalyzer?
  private var transcriber: SpeechTranscriber?
  private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
  private var resultTask: Task<Void, Never>?
  private var reservedLocale: Locale?
  private var isTapInstalled = false
  private var isStopping = false
  private var finalTranscript = ""
  private var volatileTranscript = ""
  private var interruptionObserver: NSObjectProtocol?
  private var routeChangeObserver: NSObjectProtocol?

  init(
    audioSessionCoordinator: RoutineAudioSessionCoordinator = RoutineAudioSessionCoordinator()
  ) {
    self.audioSessionCoordinator = audioSessionCoordinator
  }

  func start() async throws {
    guard await AVAudioApplication.requestRecordPermission() else {
      throw AppleSpeechRecognitionSessionError.microphonePermissionDenied
    }

    guard let supportedLocale = await SpeechTranscriber.supportedLocale(
      equivalentTo: locale
    ) else {
      throw AppleSpeechRecognitionSessionError.localeUnavailable
    }

    let transcriber = SpeechTranscriber(
      locale: supportedLocale,
      preset: .progressiveTranscription
    )
    let modules: [any SpeechModule] = [transcriber]

    try await installAssetsIfNeeded(for: modules)
    guard try await AssetInventory.reserve(locale: supportedLocale) else {
      throw AppleSpeechRecognitionSessionError.localeUnavailable
    }
    reservedLocale = supportedLocale

    do {
      try await audioSessionCoordinator.activateForSpeechInput()
    } catch {
      cleanup()
      throw AppleSpeechRecognitionSessionError.audioSession
    }

    let inputNode = audioEngine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0 else {
      cleanup()
      throw AppleSpeechRecognitionSessionError.audioSession
    }

    guard let analysisFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
      compatibleWith: modules,
      considering: inputFormat
    ) else {
      cleanup()
      throw AppleSpeechRecognitionSessionError.recognition
    }

    let analyzer = SpeechAnalyzer(modules: modules)
    do {
      try await analyzer.prepareToAnalyze(in: analysisFormat)
    } catch {
      cleanup()
      throw AppleSpeechRecognitionSessionError.recognition
    }

    let inputStream = AsyncStream<AnalyzerInput>(bufferingPolicy: .bufferingNewest(8)) {
      [weak self] continuation in
      self?.inputContinuation = continuation
    }

    self.analyzer = analyzer
    self.transcriber = transcriber
    observeAudioSessionChanges()
    startReceivingResults(from: transcriber)
    installInputTap(on: inputNode, format: analysisFormat)

    do {
      try await analyzer.start(inputSequence: inputStream)
      audioEngine.prepare()
      try audioEngine.start()
    } catch {
      cleanup()
      throw AppleSpeechRecognitionSessionError.audioSession
    }
  }

  func finish() async throws -> String {
    guard let analyzer else {
      return ""
    }

    isStopping = true
    removeInputTap()
    audioEngine.stop()
    inputContinuation?.finish()
    inputContinuation = nil

    do {
      try await analyzer.finalizeAndFinishThroughEndOfInput()
      await resultTask?.value
      let transcript = preferredTranscript()
      cleanup()
      return transcript
    } catch {
      cleanup()
      throw AppleSpeechRecognitionSessionError.recognition
    }
  }

  func cancel() {
    isStopping = true
    removeInputTap()
    audioEngine.stop()
    inputContinuation?.finish()
    inputContinuation = nil
    resultTask?.cancel()
    resultTask = nil

    if let analyzer {
      Task {
        await analyzer.cancelAndFinishNow()
      }
    }

    cleanup()
  }

  private func installAssetsIfNeeded(for modules: [any SpeechModule]) async throws {
    switch await AssetInventory.status(forModules: modules) {
    case .installed:
      return

    case .supported, .downloading:
      do {
        let request = try await AssetInventory.assetInstallationRequest(supporting: modules)
        try await request?.downloadAndInstall()
      } catch {
        throw AppleSpeechRecognitionSessionError.modelDownloadFailed
      }

    case .unsupported:
      throw AppleSpeechRecognitionSessionError.localeUnavailable

    @unknown default:
      throw AppleSpeechRecognitionSessionError.modelDownloadFailed
    }
  }

  private func installInputTap(on inputNode: AVAudioInputNode, format: AVAudioFormat) {
    inputNode.installTap(
      onBus: 0,
      bufferSize: Metric.audioBufferSize,
      format: format
    ) { [weak self] buffer, _ in
      let normalizedLevel = Self.normalizedLevel(from: buffer)
      self?.inputContinuation?.yield(AnalyzerInput(buffer: buffer))

      Task { @MainActor [weak self] in
        self?.eventHandler?(.audioLevel(normalizedLevel))
      }
    }
    isTapInstalled = true
  }

  private func removeInputTap() {
    guard isTapInstalled else {
      return
    }

    audioEngine.inputNode.removeTap(onBus: 0)
    isTapInstalled = false
  }

  private func startReceivingResults(from transcriber: SpeechTranscriber) {
    resultTask = Task { [weak self] in
      do {
        for try await result in transcriber.results {
          self?.handle(result)
        }
      } catch {
        guard let self, !self.isStopping else {
          return
        }

        self.eventHandler?(.failed(.recognition))
      }
    }
  }

  private func handle(_ result: SpeechTranscriber.Result) {
    let transcript = String(result.text.characters)

    if result.isFinal {
      finalTranscript = transcript
      volatileTranscript = ""
    } else {
      volatileTranscript = transcript
    }

    eventHandler?(.transcript(transcript, isFinal: result.isFinal))
  }

  private func observeAudioSessionChanges() {
    let notificationCenter = NotificationCenter.default
    interruptionObserver = notificationCenter.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.eventHandler?(.interrupted)
      }
    }
    routeChangeObserver = notificationCenter.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.eventHandler?(.routeChanged)
      }
    }
  }

  private func preferredTranscript() -> String {
    let transcript = finalTranscript.isEmpty ? volatileTranscript : finalTranscript
    return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func cleanup() {
    removeInputTap()
    audioEngine.stop()
    inputContinuation?.finish()
    inputContinuation = nil
    resultTask?.cancel()
    resultTask = nil
    analyzer = nil
    transcriber = nil
    audioSessionCoordinator.deactivateSpeechInput()

    if let reservedLocale {
      Task {
        await AssetInventory.release(reservedLocale: reservedLocale)
      }
      self.reservedLocale = nil
    }

    NotificationCenter.default.removeObserver(interruptionObserver as Any)
    NotificationCenter.default.removeObserver(routeChangeObserver as Any)
    interruptionObserver = nil
    routeChangeObserver = nil
  }

  nonisolated private static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Float {
    guard let channelData = buffer.floatChannelData else {
      return 0
    }

    let sampleCount = Int(buffer.frameLength)
    guard sampleCount > 0 else {
      return 0
    }

    let samples = Array(UnsafeBufferPointer(start: channelData[0], count: sampleCount))
    return SpeechAudioLevelProcessor.normalizedLevel(for: samples)
  }
}
