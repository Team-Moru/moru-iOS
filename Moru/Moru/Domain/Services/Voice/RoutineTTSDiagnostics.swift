//
//  RoutineTTSDiagnostics.swift
//  Moru
//

import Foundation
import OSLog

/// The result of the bounded foreground wait that precedes a server-only
/// routine cue. Keeping the result explicit prevents callers from treating a
/// missing or still-generating cue as a successfully completed silent cue.
nonisolated enum RoutineTTSForegroundPreparationStatus: Equatable, Sendable {
  case prepared
  case retryablePending
  case unavailable
  case cancelled
}

/// Events are intentionally identifier- and URL-free so they can be read from
/// a TestFlight device console without disclosing account or routine content.
nonisolated enum RoutineTTSDiagnosticEvent: String, Sendable {
  case cachePlanMissing
  case missingGroupBinding
  /// No binding AND no createRoutineGroup mutation record exists at all for
  /// this local group. Distinguishes "sync never even recorded intent" from
  /// the other missingGroupBinding causes below.
  case missingGroupBindingNoMutationRecord
  /// A createRoutineGroup mutation exists but is in the terminal `.blocked`
  /// state, which never resolves automatically.
  case missingGroupBindingMutationBlocked
  /// A binding record exists but failed identity/shape validation
  /// (wrong member, namespace, or remoteID) rather than being absent.
  case missingGroupBindingInvalidExistingBinding
  case missingRoutineBinding
  case remoteFetchFailed
  case responseUnavailable
  case waitingForBinding
  case waitingForGeneration
  case foregroundPrepared
  case foregroundRetryExhausted
  case audioDownloadFailed
  case voiceCacheInvalidated
  case cachePurgeFailed
  case customCueUnavailable
  case serverCueUnavailable
  /// The done/remind server-voice common cue's plan was not yet prepared
  /// when playback needed it. Fails open (silently completes) by design.
  case commonCueUnavailableForServerVoice
  /// A common cue's local file was already cache-validated but failed to
  /// start playback at cue time. Also fails open by design.
  case commonCueLateFailure
}

nonisolated struct RoutineTTSDiagnostics: Sendable {
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.teammoru.Moru",
    category: "RoutineTTS"
  )

  func record(_ event: RoutineTTSDiagnosticEvent) {
    logger.notice(
      "Routine TTS: \(event.rawValue, privacy: .public)"
    )
  }
}
