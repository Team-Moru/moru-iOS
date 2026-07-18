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
      PersistedScheduledAlarmStartObservation.self,
      PersistedHomeWeatherSnapshot.self,
      PersistedLocalSettings.self,
      PersistedAlarmRootChainState.self,
      PersistedAlarmPlatformState.self
    ]
  }
}

enum MoruMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] {
    [MoruSchemaV1.self, MoruSchemaV2.self]
  }

  static var stages: [MigrationStage] {
    [
      .custom(
        fromVersion: MoruSchemaV1.self,
        toVersion: MoruSchemaV2.self,
        willMigrate: { context in
          let schedules = try context.fetch(FetchDescriptor<PersistedAlarmSchedule>())
          schedules.forEach {
            $0.includeWeather = false
            $0.includeFortune = false
          }
          try context.save()
        },
        didMigrate: { context in
          let profiles = try context.fetch(FetchDescriptor<PersistedLocalProfile>())
          let settings = try context.fetch(FetchDescriptor<PersistedLocalSettings>())
          let profileIDsWithSettings = Set(settings.map(\.profileID))

          for profile in profiles where !profileIDsWithSettings.contains(profile.id) {
            context.insert(PersistedLocalSettings(id: profile.id, profileID: profile.id))
          }
          try context.save()
        }
      )
    ]
  }
}

extension ModelContainer {
  nonisolated static func moruContainer(
    isStoredInMemoryOnly: Bool = false,
    storeURL: URL? = nil
  ) throws -> ModelContainer {
    let schema = Schema(versionedSchema: MoruSchemaV2.self)
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
