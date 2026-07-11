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
  static func moruContainer(
    isStoredInMemoryOnly: Bool = false,
    storeURL: URL? = nil
  ) throws -> ModelContainer {
    let schema = Schema(versionedSchema: MoruSchemaV1.self)
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
