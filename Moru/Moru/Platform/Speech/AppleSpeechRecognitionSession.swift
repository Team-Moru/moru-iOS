//
//  AppleSpeechRecognitionSession.swift
//  Moru
//

import AVFAudio
import Foundation
import OSLog
import Speech

enum AppleSpeechRecognitionSessionError: Error {
  case microphonePermissionDenied
  case transcriberUnavailable
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

  nonisolated private final class AudioInputSink: @unchecked Sendable {
    private final class ConverterInput: @unchecked Sendable {
      let buffer: AVAudioPCMBuffer
      var hasBeenSupplied = false

      init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
      }
    }

    private let converter: AVAudioConverter
    private let analyzerFormat: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let onConversionFailure: @Sendable () -> Void
    private var didFail = false

    init(
      converter: AVAudioConverter,
      analyzerFormat: AVAudioFormat,
      continuation: AsyncStream<AnalyzerInput>.Continuation,
      onConversionFailure: @escaping @Sendable () -> Void
    ) {
      self.converter = converter
      self.analyzerFormat = analyzerFormat
      self.continuation = continuation
      self.onConversionFailure = onConversionFailure
    }

    func installTap(
      on inputNode: AVAudioInputNode,
      format: AVAudioFormat,
      bufferSize: AVAudioFrameCount,
      reportAudioLevels: @escaping @Sendable ([Float]) -> Void
    ) {
      inputNode.installTap(
        onBus: 0,
        bufferSize: bufferSize,
        format: format
      ) { [self] buffer, _ in
        let normalizedLevels = Self.normalizedLevels(from: buffer)
        yieldConvertedInput(from: buffer)
        reportAudioLevels(normalizedLevels)
      }
    }

    func yieldConvertedInput(from buffer: AVAudioPCMBuffer) {
      guard !didFail else {
        return
      }

      let outputFrameCapacity = AVAudioFrameCount(
        max(
          1,
          ceil(
            Double(buffer.frameLength) * analyzerFormat.sampleRate
              / buffer.format.sampleRate
          )
        )
      )
      guard let outputBuffer = AVAudioPCMBuffer(
        pcmFormat: analyzerFormat,
        frameCapacity: outputFrameCapacity
      ) else {
        reportConversionFailure()
        return
      }

      let converterInput = ConverterInput(buffer: buffer)
      var conversionError: NSError?
      let status = converter.convert(
        to: outputBuffer,
        error: &conversionError
      ) { _, inputStatus in
        guard !converterInput.hasBeenSupplied else {
          inputStatus.pointee = .noDataNow
          return nil
        }

        converterInput.hasBeenSupplied = true
        inputStatus.pointee = .haveData
        return converterInput.buffer
      }
      guard status != .error, conversionError == nil else {
        reportConversionFailure()
        return
      }

      guard outputBuffer.frameLength > 0 else {
        return
      }

      continuation.yield(AnalyzerInput(buffer: outputBuffer))
    }

    private func reportConversionFailure() {
      guard !didFail else {
        return
      }

      didFail = true
      onConversionFailure()
    }

    private static func normalizedLevels(from buffer: AVAudioPCMBuffer) -> [Float] {
      guard let channelData = buffer.floatChannelData else {
        return Array(repeating: .zero, count: 20)
      }

      let sampleCount = Int(buffer.frameLength)
      guard sampleCount > 0 else {
        return Array(repeating: .zero, count: 20)
      }

      return (0..<20).map { index in
        let start = index * sampleCount / 20
        let end = (index + 1) * sampleCount / 20
        let samples = UnsafeBufferPointer(
          start: channelData[0].advanced(by: start),
          count: end - start
        )
        return SpeechAudioLevelProcessor.normalizedLevel(for: samples)
      }
    }
  }

  var eventHandler: ((SpeechInputSessionEvent) -> Void)?

  private let audioEngine = AVAudioEngine()
  private let audioSessionCoordinator: RoutineAudioSessionCoordinator
  private let locale = Locale(identifier: "ko-KR")
#if DEBUG
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.teammoru.Moru",
    category: "SpeechRecognition"
  )
#endif
  private var analyzer: SpeechAnalyzer?
  private var transcriber: SpeechTranscriber?
  private var inputSink: AudioInputSink?
  private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
  private var resultTask: Task<Void, Never>?
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

    await logDeviceSupport()
    guard SpeechTranscriber.isAvailable else {
      log("SpeechTranscriber is unavailable on this device")
      throw AppleSpeechRecognitionSessionError.transcriberUnavailable
    }

    guard let supportedLocale = await SpeechTranscriber.supportedLocale(
      equivalentTo: locale
    ) else {
      log("Requested locale is not supported: \(locale.identifier(.bcp47))")
      throw AppleSpeechRecognitionSessionError.localeUnavailable
    }

    let transcriber = SpeechTranscriber(
      locale: supportedLocale,
      preset: .progressiveTranscription
    )
    let modules: [any SpeechModule] = [transcriber]

    try await installAssetsIfNeeded(for: modules)

    do {
      try await audioSessionCoordinator.activateForSpeechInput()
    } catch {
      cleanup()
      throw AppleSpeechRecognitionSessionError.audioSession
    }

    let inputNode = audioEngine.inputNode
    // AVAudioInputNode exposes the physical microphone format on its input scope.
    let hardwareInputFormat = inputNode.inputFormat(forBus: 0)
    let tapFormat = inputNode.outputFormat(forBus: 0)
    guard
      hardwareInputFormat.sampleRate > 0,
      hardwareInputFormat.channelCount > 0,
      tapFormat.sampleRate > 0,
      tapFormat.channelCount > 0,
      hardwareInputFormat.isEqual(tapFormat)
    else {
      cleanup()
      throw AppleSpeechRecognitionSessionError.audioSession
    }

    guard let analysisFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
      compatibleWith: modules,
      considering: tapFormat
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

    guard let audioConverter = AVAudioConverter(
      from: tapFormat,
      to: analysisFormat
    ) else {
      cleanup()
      throw AppleSpeechRecognitionSessionError.recognition
    }
    audioConverter.primeMethod = .none

    let inputStream = AsyncStream<AnalyzerInput>(bufferingPolicy: .bufferingNewest(8)) {
      [weak self] continuation in
      self?.inputContinuation = continuation
    }
    guard let inputContinuation else {
      cleanup()
      throw AppleSpeechRecognitionSessionError.recognition
    }

    let inputSink = AudioInputSink(
      converter: audioConverter,
      analyzerFormat: analysisFormat,
      continuation: inputContinuation,
      onConversionFailure: { [weak self] in
        Task { @MainActor [weak self] in
          self?.handleInputConversionFailure()
        }
      }
    )
    let reportAudioLevels: @Sendable ([Float]) -> Void = { [weak self] levels in
      Task { @MainActor [weak self] in
        self?.eventHandler?(.audioLevels(levels))
      }
    }

    self.analyzer = analyzer
    self.transcriber = transcriber
    self.inputSink = inputSink
    observeAudioSessionChanges()
    startReceivingResults(from: transcriber)
    installInputTap(
      on: inputNode,
      format: tapFormat,
      inputSink: inputSink,
      reportAudioLevels: reportAudioLevels
    )

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

    do {
      inputContinuation?.finish()
      inputContinuation = nil
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
    let initialStatus = await AssetInventory.status(forModules: modules)
    await logAssetStatus(initialStatus)

    switch initialStatus {
    case .installed:
      return

    case .supported, .downloading:
      do {
        let request = try await AssetInventory.assetInstallationRequest(supporting: modules)
        try await request?.downloadAndInstall()
      } catch {
        log("Speech asset installation failed")
        throw AppleSpeechRecognitionSessionError.modelDownloadFailed
      }

    case .unsupported:
      log("Speech asset configuration is unsupported")
      throw AppleSpeechRecognitionSessionError.localeUnavailable

    @unknown default:
      log("Speech asset configuration returned an unknown status")
      throw AppleSpeechRecognitionSessionError.modelDownloadFailed
    }

    let finalStatus = await AssetInventory.status(forModules: modules)
    await logAssetStatus(finalStatus)
    switch finalStatus {
    case .installed:
      return
    case .unsupported:
      log("Speech asset configuration became unsupported after installation")
      throw AppleSpeechRecognitionSessionError.localeUnavailable
    case .supported, .downloading:
      log("Speech assets did not finish installing")
      throw AppleSpeechRecognitionSessionError.modelDownloadFailed
    @unknown default:
      log("Speech asset configuration returned an unknown post-install status")
      throw AppleSpeechRecognitionSessionError.modelDownloadFailed
    }
  }

  private func installInputTap(
    on inputNode: AVAudioInputNode,
    format: AVAudioFormat,
    inputSink: AudioInputSink,
    reportAudioLevels: @escaping @Sendable ([Float]) -> Void
  ) {
    inputSink.installTap(
      on: inputNode,
      format: format,
      bufferSize: Metric.audioBufferSize,
      reportAudioLevels: reportAudioLevels
    )
    isTapInstalled = true
  }

  private func handleInputConversionFailure() {
    guard !isStopping else {
      return
    }

    log("Speech input conversion failed")
    eventHandler?(.failed(.recognition))
    cancel()
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
    inputSink = nil
    audioSessionCoordinator.deactivateSpeechInput()

    NotificationCenter.default.removeObserver(interruptionObserver as Any)
    NotificationCenter.default.removeObserver(routeChangeObserver as Any)
    interruptionObserver = nil
    routeChangeObserver = nil
  }

  private func logDeviceSupport() async {
#if DEBUG
    let requestedLocale = locale.identifier(.bcp47)
    let supportedLocales = await SpeechTranscriber.supportedLocales
    let installedLocales = await SpeechTranscriber.installedLocales
    let supportsRequestedLocale = supportedLocales.contains {
      $0.identifier(.bcp47) == requestedLocale
    }
    let hasInstalledRequestedLocale = installedLocales.contains {
      $0.identifier(.bcp47) == requestedLocale
    }
    let message = "Speech support | available=\(SpeechTranscriber.isAvailable) "
      + "requested=\(requestedLocale) "
      + "supportsRequested=\(supportsRequestedLocale) "
      + "installedRequested=\(hasInstalledRequestedLocale) "
      + "supportedCount=\(supportedLocales.count) "
      + "installedCount=\(installedLocales.count)"
    Self.logger.debug("\(message, privacy: .public)")
#endif
  }

  private func logAssetStatus(_ status: AssetInventory.Status) async {
#if DEBUG
    let reservedLocales = await AssetInventory.reservedLocales
    let message = "Speech assets | status=\(String(describing: status)) "
      + "reservedCount=\(reservedLocales.count) "
      + "maximumReservedLocales=\(AssetInventory.maximumReservedLocales)"
    Self.logger.debug("\(message, privacy: .public)")
#endif
  }

  private func log(_ message: String) {
#if DEBUG
    Self.logger.debug("\(message, privacy: .public)")
#endif
  }
}
