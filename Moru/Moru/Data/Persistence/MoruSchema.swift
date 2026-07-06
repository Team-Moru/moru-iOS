//
//  MoruSchema.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import SwiftData

enum MoruSchemaV1: VersionedSchema {
  static let versionIdentifier = Schema.Version(1, 0, 0)

  static var models: [any PersistentModel.Type] {
    [
      PersistedRoutine.self,
      PersistedRoutineStep.self,
      PersistedAlarmSchedule.self,
      PersistedRoutineRun.self,
      PersistedRoutineStepResult.self,
      PersistedLocalProfile.self
    ]
  }
}

enum MoruMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] {
    [MoruSchemaV1.self]
  }

  static var stages: [MigrationStage] {
    []
  }
}

extension ModelContainer {
  @MainActor
  static func moruContainer(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
    let schema = Schema(versionedSchema: MoruSchemaV1.self)
    let configuration = ModelConfiguration(
      "Moru",
      schema: schema,
      isStoredInMemoryOnly: isStoredInMemoryOnly,
      cloudKitDatabase: .none
    )

    return try ModelContainer(
      for: schema,
      migrationPlan: MoruMigrationPlan.self,
      configurations: [configuration]
    )
  }
}
