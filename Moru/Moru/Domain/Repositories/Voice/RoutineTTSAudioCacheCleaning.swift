//
//  RoutineTTSAudioCacheCleaning.swift
//  Moru
//

import Foundation

/// Product-level cleanup boundary. Cached server audio is recoverable and
/// must never make local reset or account transitions depend on its contents.
nonisolated protocol RoutineTTSAudioCacheCleaning: Sendable {
  func removeAllRoutineTTSAudio() async throws
  func removeRoutineTTSAudio(memberID: Int64) async throws
}

nonisolated extension RoutineTTSAudioCacheCleaning {
  func removeRoutineTTSAudio(memberID: Int64) async throws {
    try await removeAllRoutineTTSAudio()
  }
}
