//
//  MoruSchema.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData

enum MoruSchemaV1: VersionedSchema {
  static let versionIdentifier = Schema.Version(1, 0, 0)

  static var models: [any PersistentModel.Type] {
    [
      PersistedRoutine.self,
      PersistedRoutineStep.self,
      PersistedAlarmSchedule.self,
      PersistedRoutineRun.self,
      PersistedRoutineStepSnapshot.self,
      PersistedRoutineStepResult.self,
      PersistedLocalProfile.self
    ]
  }
}

enum MoruSchemaV2: VersionedSchema {
  static let versionIdentifier = Schema.Version(2, 0, 0)

  static var models: [any PersistentModel.Type] {
    [
      PersistedRoutine.self,
      PersistedRoutineStep.self,
      PersistedAlarmSchedule.self,
      PersistedRoutineRun.self,
      PersistedRoutineStepSnapshot.self,
      PersistedRoutineStepResult.self,
      PersistedLocalProfile.self,
      PersistedHomeWeatherSnapshot.self
    ]
  }
}

enum MoruSchemaV3: VersionedSchema {
  static let versionIdentifier = Schema.Version(3, 0, 0)

  static var models: [any PersistentModel.Type] {
    [
      PersistedRoutine.self,
      PersistedRoutineStep.self,
      PersistedAlarmSchedule.self,
      PersistedRoutineRun.self,
      PersistedRoutineStepSnapshot.self,
      PersistedRoutineStepResult.self,
      PersistedLocalProfile.self,
      PersistedHomeWeatherSnapshot.self,
      PersistedAlarmPlatformState.self,
      PersistedSnoozedAlarm.self,
    ]
  }
}

enum MoruSchemaV4: VersionedSchema {
  static let versionIdentifier = Schema.Version(4, 0, 0)

  static var models: [any PersistentModel.Type] {
    [
      PersistedRoutine.self,
      PersistedRoutineStep.self,
      PersistedAlarmSchedule.self,
      PersistedRoutineRun.self,
      PersistedRoutineStepSnapshot.self,
      PersistedRoutineStepResult.self,
      PersistedLocalProfile.self,
      PersistedHomeWeatherSnapshot.self,
      PersistedAlarmPlatformState.self,
      PersistedSnoozedAlarm.self,
      PersistedRoutineServerBinding.self,
      PersistedRoutineSyncMutation.self,
      PersistedPendingAccountCleanup.self,
    ]
  }
}

enum MoruSchemaV5: VersionedSchema {
  static let versionIdentifier = Schema.Version(5, 0, 0)

  static var models: [any PersistentModel.Type] {
    MoruSchemaV4.models + [PersistedRoutineSyncAttemptArtifact.self]
  }
}

enum MoruSchemaV6: VersionedSchema {
  static let versionIdentifier = Schema.Version(6, 0, 0)

  static var models: [any PersistentModel.Type] {
    MoruSchemaV5.models + [PersistedProvisionalOnboardingMarker.self]
  }
}

enum MoruMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] {
    [
      MoruSchemaV1.self,
      MoruSchemaV2.self,
      MoruSchemaV3.self,
      MoruSchemaV4.self,
      MoruSchemaV5.self,
      MoruSchemaV6.self,
    ]
  }

  static var stages: [MigrationStage] {
    [
      .lightweight(fromVersion: MoruSchemaV1.self, toVersion: MoruSchemaV2.self),
      .lightweight(fromVersion: MoruSchemaV2.self, toVersion: MoruSchemaV3.self),
      .lightweight(fromVersion: MoruSchemaV3.self, toVersion: MoruSchemaV4.self),
      .lightweight(fromVersion: MoruSchemaV4.self, toVersion: MoruSchemaV5.self),
      .lightweight(fromVersion: MoruSchemaV5.self, toVersion: MoruSchemaV6.self),
    ]
  }
}

extension ModelContainer {
  @MainActor
  static func moruContainer(
    isStoredInMemoryOnly: Bool = false,
    storeURL: URL? = nil
  ) throws -> ModelContainer {
    let schema = Schema(versionedSchema: MoruSchemaV6.self)
    let configuration: ModelConfiguration

    if let storeURL {
      configuration = ModelConfiguration(
        "Moru",
        schema: schema,
        url: storeURL,
        cloudKitDatabase: .none
      )
    } else {
      configuration = ModelConfiguration(
        "Moru",
        schema: schema,
        isStoredInMemoryOnly: isStoredInMemoryOnly,
        cloudKitDatabase: .none
      )
    }

    return try ModelContainer(
      for: schema,
      migrationPlan: MoruMigrationPlan.self,
      configurations: [configuration]
    )
  }
}
