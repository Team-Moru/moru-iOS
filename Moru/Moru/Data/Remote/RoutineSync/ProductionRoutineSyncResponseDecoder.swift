//
//  ProductionRoutineSyncResponseDecoder.swift
//  Moru
//

import Foundation
import OSLog

/// Validates only identity facts returned by the production write response.
/// Local titles, schedules, and execution state remain owned by SwiftData.
nonisolated struct ProductionRoutineSyncResponseDecoder:
  RoutineSyncTransportResponseDecoding,
  Sendable {
  private let decoder = JSONDecoder()
  /// `PATCH .../active`'s success code was never observed against the live
  /// server (every attempt this session failed earlier at group creation),
  /// so this logs the actual code on mismatch instead of failing silently
  /// indistinguishable from any other invalidResponse cause.
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.teammoru.Moru",
    category: "RoutineSyncResponseDecoder"
  )

  func decodeCommit(
    for request: RoutineSyncTransportRequest,
    from responseData: Data
  ) throws -> RoutineSyncTransportCommit {
    let metadata: ProductionRoutineSyncEnvelopeMetadata
    do {
      metadata = try decoder.decode(
        ProductionRoutineSyncEnvelopeMetadata.self,
        from: responseData
      )
    } catch {
      throw RoutineSyncResponseDecodingError.invalidResponse
    }

    guard metadata.isSuccess else {
      switch metadata.code {
      case "COMMON409":
        throw RoutineSyncResponseDecodingError.processingConflict
      case "COMMON410":
        throw RoutineSyncResponseDecodingError.idempotencyPayloadConflict
      default:
        throw RoutineSyncResponseDecodingError.definitiveServerRejection
      }
    }

    switch request.command {
    case .createRoutineGroup(let group):
      guard request.operation == .createRoutineGroup,
            request.wireRequest.method == .post,
            request.wireRequest.path == "/routine-groups",
            metadata.code == "COMMON201" else {
        throw RoutineSyncResponseDecodingError.invalidResponse
      }
      return try decodeCreatedGroup(
        group,
        from: responseData
      )

    case .addRoutine(let groupLocalID, let routine):
      guard request.operation == .addRoutine,
            request.wireRequest.method == .post,
            let parentRemoteID = remoteID(
              in: request.wireRequest.path,
              prefix: "/routine-groups/",
              suffix: "/routines"
            ),
            metadata.code == "COMMON201" else {
        throw RoutineSyncResponseDecodingError.invalidResponse
      }
      return try decodeAddedRoutine(
        groupLocalID: groupLocalID,
        parentRemoteID: parentRemoteID,
        routine: routine,
        from: responseData
      )

    case .deleteRoutineGroup:
      guard request.operation == .deleteRoutineGroup,
            request.wireRequest.method == .delete,
            request.wireRequest.body.isEmpty,
            let expectedRemoteID = remoteID(
              in: request.wireRequest.path,
              prefix: "/routine-groups/"
            ),
            metadata.code == "COMMON200" else {
        throw RoutineSyncResponseDecodingError.invalidResponse
      }
      try validateDelete(
        expectedRemoteID: expectedRemoteID,
        kind: .routineGroup,
        responseData: responseData
      )
      return .deleted

    case .deleteRoutine:
      guard request.operation == .deleteRoutine,
            request.wireRequest.method == .delete,
            request.wireRequest.body.isEmpty,
            let expectedRemoteID = remoteID(
              in: request.wireRequest.path,
              prefix: "/routines/"
            ),
            metadata.code == "COMMON200" else {
        throw RoutineSyncResponseDecodingError.invalidResponse
      }
      try validateDelete(
        expectedRemoteID: expectedRemoteID,
        kind: .routine,
        responseData: responseData
      )
      return .deleted

    case .saveRoutineExecution(let execution):
      guard request.operation == .saveRoutineExecution,
            request.wireRequest.method == .post,
            request.wireRequest.path == "/routine-executions",
            metadata.code == "COMMON201" else {
        throw RoutineSyncResponseDecodingError.invalidResponse
      }
      return try decodeSavedExecution(
        execution,
        requestBody: request.wireRequest.body,
        responseData: responseData
      )

    case .completeOnboarding:
      guard request.operation == .completeOnboarding,
            request.wireRequest.method == .post,
            request.wireRequest.path == "/onboarding/complete",
            metadata.code == "COMMON200" else {
        throw RoutineSyncResponseDecodingError.invalidResponse
      }
      let completionRequest: ProductionOnboardingCompletionRequestDTO
      do {
        completionRequest = try decoder.decode(
          ProductionOnboardingCompletionRequestDTO.self,
          from: request.wireRequest.body
        )
      } catch {
        throw RoutineSyncResponseDecodingError.invalidResponse
      }
      guard completionRequest.routineGroupId > 0 else {
        throw RoutineSyncResponseDecodingError.invalidResponse
      }
      let envelope: ProductionRoutineSyncEnvelope<
        ProductionOnboardingCompletionResponseDTO
      > = try decodeEnvelope(from: responseData)
      guard envelope.result?.onboardingCompleted == true else {
        throw RoutineSyncResponseDecodingError.invalidResponse
      }
      return .onboardingCompleted

    case .selectActiveRoutineGroup(let selectedGroupLocalID):
      guard request.operation == .setRoutineGroupActive,
            request.wireRequest.method == .patch,
            let selectedGroupLocalID,
            let expectedRemoteID = remoteID(
              in: request.wireRequest.path,
              prefix: "/routine-groups/",
              suffix: "/active"
            ) else {
        throw RoutineSyncResponseDecodingError.invalidResponse
      }
      guard metadata.code == "COMMON200" else {
        Self.logger.notice(
          "PATCH .../active succeeded with unexpected code: \(metadata.code, privacy: .public)"
        )
        throw RoutineSyncResponseDecodingError.invalidResponse
      }
      try validateActiveSelection(
        expectedRemoteID: expectedRemoteID,
        responseData: responseData
      )
      // No new local/server ID pair is created by activation; the group's
      // binding already exists from its own createRoutineGroup settlement.
      return .mutation(assignments: [])
    }
  }

  private func validateActiveSelection(
    expectedRemoteID: Int64,
    responseData: Data
  ) throws {
    let envelope: ProductionRoutineSyncEnvelope<
      ProductionRoutineGroupActiveResponseDTO
    > = try decodeEnvelope(from: responseData)
    guard let response = envelope.result,
          response.routineGroupId == expectedRemoteID,
          response.isActive == true else {
      throw RoutineSyncResponseDecodingError.invalidResponse
    }
  }

  private func decodeSavedExecution(
    _ expected: RoutineSyncExecutionSnapshot,
    requestBody: Data,
    responseData: Data
  ) throws -> RoutineSyncTransportCommit {
    let requestIdentity: ProductionRoutineExecutionRequestIdentityDTO
    do {
      requestIdentity = try decoder.decode(
        ProductionRoutineExecutionRequestIdentityDTO.self,
        from: requestBody
      )
    } catch {
      throw RoutineSyncResponseDecodingError.invalidResponse
    }
    let envelope: ProductionRoutineSyncEnvelope<
      ProductionRoutineExecutionResponseDTO
    > = try decodeEnvelope(from: responseData)
    guard expected.runCompletedAt != nil,
          expected.result.completedAt != nil || expected.result.skipped,
          let response = envelope.result,
          let executionRemoteID = positive(response.executionId),
          response.routineId == requestIdentity.routineId,
          response.executedDate == requestIdentity.executedDate,
          response.durationSecond == requestIdentity.durationSecond,
          response.isCompleted == requestIdentity.isCompleted else {
      throw RoutineSyncResponseDecodingError.invalidResponse
    }
    return .mutation(
      assignments: [
        RoutineServerBindingAssignment(
          entityKind: .routineExecution,
          localEntityID: expected.result.localID,
          remoteID: executionRemoteID,
          parentEntityKind: .routine,
          parentLocalEntityID: expected.routineLocalID
        ),
      ]
    )
  }

  private func decodeCreatedGroup(
    _ expected: RoutineSyncGroupSnapshot,
    from responseData: Data
  ) throws -> RoutineSyncTransportCommit {
    let envelope: ProductionRoutineSyncEnvelope<
      ProductionRoutineGroupCreateResponseDTO
    > = try decodeEnvelope(from: responseData)
    guard let response = envelope.result,
          let groupRemoteID = positive(response.routineGroupId),
          let groupLocalID = parsed(response.clientEntityId),
          groupLocalID == expected.localID,
          let routines = response.routines,
          !expected.routines.isEmpty,
          routines.count == expected.routines.count else {
      throw RoutineSyncResponseDecodingError.invalidResponse
    }

    let expectedLocalIDs = expected.routines.map(\.localID)
    guard Set(expectedLocalIDs).count == expectedLocalIDs.count,
          !Set(expectedLocalIDs).contains(expected.localID) else {
      throw RoutineSyncResponseDecodingError.invalidResponse
    }

    var seenLocalIDs = Set<UUID>()
    var seenRemoteIDs: Set<Int64> = [groupRemoteID]
    var assignments = [
      RoutineServerBindingAssignment(
        entityKind: .routineGroup,
        localEntityID: expected.localID,
        remoteID: groupRemoteID
      ),
    ]

    for routineResponse in routines {
      guard let localID = parsed(routineResponse.clientEntityId),
            seenLocalIDs.insert(localID).inserted,
            let expectedRoutine = expected.routines.first(where: {
              $0.localID == localID
            }),
            routineResponse.type == serverType(for: expectedRoutine.type),
            let remoteID = positive(routineResponse.routineId),
            seenRemoteIDs.insert(remoteID).inserted else {
        throw RoutineSyncResponseDecodingError.invalidResponse
      }
      assignments.append(
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: localID,
          remoteID: remoteID,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: expected.localID
        )
      )
    }

    guard seenLocalIDs == Set(expectedLocalIDs) else {
      throw RoutineSyncResponseDecodingError.invalidResponse
    }
    return .createRoutineGroup(assignments: assignments)
  }

  private func decodeAddedRoutine(
    groupLocalID: UUID,
    parentRemoteID: Int64,
    routine expected: RoutineSyncRoutineSnapshot,
    from responseData: Data
  ) throws -> RoutineSyncTransportCommit {
    let envelope: ProductionRoutineSyncEnvelope<
      ProductionRoutineResponseDTO
    > = try decodeEnvelope(from: responseData)
    guard groupLocalID != expected.localID,
          let response = envelope.result,
          let localID = parsed(response.clientEntityId),
          localID == expected.localID,
          response.type == serverType(for: expected.type),
          let remoteID = positive(response.routineId),
          remoteID != parentRemoteID else {
      throw RoutineSyncResponseDecodingError.invalidResponse
    }
    return .mutation(
      assignments: [
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: localID,
          remoteID: remoteID,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupLocalID
        ),
      ]
    )
  }

  private func validateDelete(
    expectedRemoteID: Int64,
    kind: RoutineSyncEntityKind,
    responseData: Data
  ) throws {
    let envelope: ProductionRoutineSyncEnvelope<
      ProductionRoutineDeleteResponseDTO
    > = try decodeEnvelope(from: responseData)
    guard let response = envelope.result else {
      throw RoutineSyncResponseDecodingError.invalidResponse
    }
    switch kind {
    case .routineGroup:
      guard response.routineGroupId == expectedRemoteID,
            response.routineId == nil else {
        throw RoutineSyncResponseDecodingError.invalidResponse
      }
    case .routine:
      guard response.routineId == expectedRemoteID,
            response.routineGroupId == nil else {
        throw RoutineSyncResponseDecodingError.invalidResponse
      }
    case .account, .routineExecution:
      throw RoutineSyncResponseDecodingError.invalidResponse
    }
  }

  private func decodeEnvelope<Payload: Decodable & Sendable>(
    from data: Data
  ) throws -> ProductionRoutineSyncEnvelope<Payload> {
    do {
      return try decoder.decode(
        ProductionRoutineSyncEnvelope<Payload>.self,
        from: data
      )
    } catch {
      throw RoutineSyncResponseDecodingError.invalidResponse
    }
  }

  private func remoteID(
    in path: String,
    prefix: String,
    suffix: String = ""
  ) -> Int64? {
    guard path.hasPrefix(prefix), path.hasSuffix(suffix) else { return nil }
    let start = path.index(path.startIndex, offsetBy: prefix.count)
    let end = suffix.isEmpty
      ? path.endIndex
      : path.index(path.endIndex, offsetBy: -suffix.count)
    guard start < end,
          let value = Int64(path[start..<end]),
          value > 0 else {
      return nil
    }
    return value
  }

  private func parsed(_ value: String?) -> UUID? {
    guard let value,
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return UUID(uuidString: value)
  }

  private func positive(_ value: Int64?) -> Int64? {
    guard let value, value > 0 else { return nil }
    return value
  }

  private func serverType(for localType: String) -> String? {
    switch localType {
    case RoutineStepType.confirm.rawValue:
      return "CHECK"
    case RoutineStepType.timer.rawValue:
      return "TIMER"
    case RoutineStepType.input.rawValue:
      return "INPUT"
    default:
      return nil
    }
  }
}

nonisolated private struct ProductionRoutineSyncEnvelopeMetadata:
  Decodable,
  Sendable {
  let isSuccess: Bool
  let code: String
}

nonisolated private struct ProductionRoutineSyncEnvelope<
  Payload: Decodable & Sendable
>: Decodable, Sendable {
  let result: Payload?
}

nonisolated private struct ProductionRoutineGroupCreateResponseDTO:
  Decodable,
  Sendable {
  let routineGroupId: Int64?
  let clientEntityId: String?
  let routines: [ProductionRoutineResponseDTO]?
}

nonisolated private struct ProductionRoutineResponseDTO:
  Decodable,
  Sendable {
  let routineId: Int64?
  let clientEntityId: String?
  let type: String?
}

nonisolated private struct ProductionRoutineDeleteResponseDTO:
  Decodable,
  Sendable {
  let routineGroupId: Int64?
  let routineId: Int64?
}

nonisolated private struct ProductionRoutineGroupActiveResponseDTO:
  Decodable,
  Sendable {
  let routineGroupId: Int64?
  let isActive: Bool?
}

nonisolated private struct ProductionRoutineExecutionRequestIdentityDTO:
  Decodable,
  Sendable {
  let executedDate: String
  let routineId: Int64
  let durationSecond: Int?
  let isCompleted: Bool
}

nonisolated private struct ProductionRoutineExecutionResponseDTO:
  Decodable,
  Sendable {
  let executedDate: String?
  let executionId: Int64?
  let routineId: Int64?
  let durationSecond: Int?
  let isCompleted: Bool?
}

nonisolated private struct ProductionOnboardingCompletionResponseDTO:
  Decodable,
  Sendable {
  let onboardingCompleted: Bool?
}

nonisolated private struct ProductionOnboardingCompletionRequestDTO:
  Decodable,
  Sendable {
  let routineGroupId: Int64
}
