//
//  RoutineTTSProvisioningRequestFactory.swift
//  Moru
//

import CryptoKit
import Foundation

enum RoutineTTSProvisioningRequestError: Error, Equatable {
  case emptyRoutineTitle
  case emptySteps
  case duplicateStepID(UUID)
  case duplicateStepOrder(Int)
  case emptyStepTitle(UUID)
  case invalidDuration(stepID: UUID, seconds: Int?)
  case fingerprintEncodingFailed
}

struct RoutineTTSProvisioningPlan: Equatable {
  let request: ServerRoutineGroupCreationRequest
  let contentFingerprint: String
}

enum RoutineTTSProvisioningRequestFactory {
  static func makePlan(
    for routine: Routine
  ) throws -> RoutineTTSProvisioningPlan {
    let title = routine.name.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !title.isEmpty else {
      throw RoutineTTSProvisioningRequestError.emptyRoutineTitle
    }

    let orderedSteps = routine.steps.sorted { lhs, rhs in
      if lhs.order == rhs.order {
        return lhs.id.uuidString < rhs.id.uuidString
      }
      return lhs.order < rhs.order
    }
    guard !orderedSteps.isEmpty else {
      throw RoutineTTSProvisioningRequestError.emptySteps
    }

    var stepIDs = Set<UUID>()
    var stepOrders = Set<Int>()
    let serverRoutines = try orderedSteps.map { step in
      guard stepIDs.insert(step.id).inserted else {
        throw RoutineTTSProvisioningRequestError.duplicateStepID(step.id)
      }
      guard stepOrders.insert(step.order).inserted else {
        throw RoutineTTSProvisioningRequestError.duplicateStepOrder(
          step.order
        )
      }

      let stepTitle = step.title.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      guard !stepTitle.isEmpty else {
        throw RoutineTTSProvisioningRequestError.emptyStepTitle(step.id)
      }
      guard let durationSeconds = step.estimatedSeconds,
            (1...Int(Int32.max)).contains(durationSeconds) else {
        throw RoutineTTSProvisioningRequestError.invalidDuration(
          stepID: step.id,
          seconds: step.estimatedSeconds
        )
      }

      return ServerRoutineCreationRequest(
        localStepID: step.id,
        title: stepTitle,
        type: serverType(for: step.type),
        durationSeconds: durationSeconds
      )
    }

    let normalizedSummary = routine.summary.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let request = ServerRoutineGroupCreationRequest(
      localRoutineID: routine.id,
      title: title,
      description: normalizedSummary.isEmpty ? nil : normalizedSummary,
      // This server group is only a temporary TTS source. Local alarms and
      // weather remain authoritative, so do not create a second schedule.
      alarmDaysRaw: nil,
      alarmTimeRaw: nil,
      weatherNotificationEnabled: false,
      routines: serverRoutines
    )

    return RoutineTTSProvisioningPlan(
      request: request,
      contentFingerprint: try fingerprint(for: request)
    )
  }

  private static func serverType(
    for type: RoutineStepType
  ) -> ServerRoutineCreationItemType {
    switch type {
    case .confirm:
      .check
    case .timer:
      .timer
    case .input:
      .input
    }
  }

  private static func fingerprint(
    for request: ServerRoutineGroupCreationRequest
  ) throws -> String {
    let payload = FingerprintPayload(
      localRoutineID: request.localRoutineID,
      title: request.title,
      description: request.description,
      alarmDaysRaw: request.alarmDaysRaw,
      alarmTimeRaw: request.alarmTimeRaw,
      weatherNotificationEnabled: request.weatherNotificationEnabled,
      routines: request.routines.map {
        FingerprintRoutine(
          localStepID: $0.localStepID,
          title: $0.title,
          type: fingerprintType(for: $0.type),
          durationSeconds: $0.durationSeconds
        )
      }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let data: Data
    do {
      data = try encoder.encode(payload)
    } catch {
      throw RoutineTTSProvisioningRequestError
        .fingerprintEncodingFailed
    }

    return SHA256.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private static func fingerprintType(
    for type: ServerRoutineCreationItemType
  ) -> String {
    switch type {
    case .check:
      "CHECK"
    case .timer:
      "TIMER"
    case .input:
      "INPUT"
    }
  }
}

private struct FingerprintPayload: Encodable {
  let localRoutineID: UUID
  let title: String
  let description: String?
  let alarmDaysRaw: String?
  let alarmTimeRaw: String?
  let weatherNotificationEnabled: Bool
  let routines: [FingerprintRoutine]
}

private struct FingerprintRoutine: Encodable {
  let localStepID: UUID
  let title: String
  let type: String
  let durationSeconds: Int
}
