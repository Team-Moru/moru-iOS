//
//  RoutineTTSCuePlanResolver.swift
//  Moru
//

import Foundation

nonisolated struct RoutineTTSResolvedAsset: Equatable, Sendable {
  let remoteRoutineID: Int64
  let remoteStepID: Int64
  let remoteURL: URL
}

nonisolated enum RoutineTTSCuePlanResolution: Equatable, Sendable {
  case unavailable
  case playable([RoutineTTSResolvedAsset])
}

/// Strictly joins local identities to the server response. Any incomplete or
/// ambiguous join is rejected so audio from another routine can never play.
nonisolated struct RoutineTTSCuePlanResolver: Sendable {
  func resolve(
    routineGroupLocalID: UUID,
    routineLocalID: UUID,
    groupBinding: RoutineServerBinding?,
    routineBinding: RoutineServerBinding?,
    response: [ServerRoutineTTSRoutine]
  ) -> RoutineTTSCuePlanResolution {
    guard let groupBinding,
          groupBinding.entityKind == .routineGroup,
          groupBinding.localEntityID == routineGroupLocalID,
          groupBinding.remoteID > 0,
          let routineBinding,
          routineBinding.entityKind == .routine,
          routineBinding.localEntityID == routineLocalID,
          routineBinding.remoteID > 0,
          routineBinding.memberID == groupBinding.memberID,
          routineBinding.serverNamespace == groupBinding.serverNamespace,
          routineBinding.parentEntityKind == .routineGroup,
          routineBinding.parentLocalEntityID == routineGroupLocalID else {
      return .unavailable
    }

    let matches = response.filter { $0.routineID == routineBinding.remoteID }
    guard matches.count == 1, let remoteRoutine = matches.first,
          !remoteRoutine.steps.isEmpty else {
      return .unavailable
    }

    var seenStepIDs = Set<Int64>()
    var assets: [RoutineTTSResolvedAsset] = []
    assets.reserveCapacity(remoteRoutine.steps.count)

    for step in remoteRoutine.steps {
      guard step.stepID > 0,
            seenStepIDs.insert(step.stepID).inserted,
            step.status == .completed,
            let audioURL = step.audioURL,
            audioURL.scheme?.lowercased() == "https",
            audioURL.host != nil else {
        return .unavailable
      }

      assets.append(RoutineTTSResolvedAsset(
        remoteRoutineID: remoteRoutine.routineID,
        remoteStepID: step.stepID,
        remoteURL: audioURL
      ))
    }

    return .playable(assets)
  }
}
