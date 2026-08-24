//
//  SwiftDataProfileMapper.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData

/// LocalProfile 매핑은 Routine/RoutineRun 매핑과 달리 공유 헬퍼
/// (v1Sync, makeSyncMetadata, makeStepType 등)를 사용하지 않아 독립적으로
/// 분리했다. 호출부는 기존과 동일하게 `SwiftDataMapper.` 네임스페이스를 쓴다.
extension SwiftDataMapper {
  static func makePersistedProfile(from profile: LocalProfile) -> PersistedLocalProfile {
    PersistedLocalProfile(
      id: profile.id,
      displayName: profile.displayName,
      selectedVoiceID: profile.selectedVoice.id,
      createdAt: profile.createdAt,
      updatedAt: profile.updatedAt
    )
  }

  static func update(_ persisted: PersistedLocalProfile, with profile: LocalProfile) {
    persisted.displayName = profile.displayName
    persisted.selectedVoiceID = profile.selectedVoice.id
    persisted.createdAt = profile.createdAt
    persisted.updatedAt = profile.updatedAt
  }

  static func makeDomainProfile(from persisted: PersistedLocalProfile) -> LocalProfile {
    LocalProfile(
      id: persisted.id,
      displayName: persisted.displayName,
      selectedVoice: VoiceProfile.fallback(id: persisted.selectedVoiceID),
      createdAt: persisted.createdAt,
      updatedAt: persisted.updatedAt
    )
  }
}
