//
//  RoutineTTSLinkRepository.swift
//  Moru
//

import Foundation

enum RoutineTTSLinkValidationError: Error, Equatable, Sendable {
  case invalidMemberID(Int64)
  case invalidServerRoutineGroupID(Int64)
  case emptyContentFingerprint
  case emptyFailureCode
  case invalidServerRoutineID(Int64)
  case invalidServerStepID(Int64)
  case invalidOrderIndex(Int)
  case invalidCachedRelativePath(String)
  case duplicateServerStepID(Int64)
  case inconsistentServerRoutineMapping(localStepID: UUID)
  case duplicateOrderIndex(localStepID: UUID, orderIndex: Int)
  case invalidCreatingState
  case invalidGeneratingState
  case invalidReadyState
}

enum RoutineTTSLinkRepositoryError: Error, Equatable, Sendable {
  case invalidStatus(String)
  case invalidManifest
  case invalidLink(RoutineTTSLinkValidationError)
}

protocol RoutineTTSLinkRepository: AnyObject {
  @MainActor
  func link(
    localRoutineID: UUID,
    memberID: Int64
  ) throws -> RoutineTTSLink?

  @MainActor
  func localRoutineIDs(memberID: Int64) throws -> [UUID]

  @MainActor
  func saveLink(_ link: RoutineTTSLink) throws

  @MainActor
  func deleteLink(localRoutineID: UUID) throws

  @MainActor
  func deleteLinks(memberID: Int64) throws

  @MainActor
  func deleteAllLinks() throws
}
