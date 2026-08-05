//
//  AccountRoutineGroupViewModels.swift
//  Moru
//

import Foundation
import Observation

nonisolated struct AccountRoutineGroupArchiveNavigationState: Equatable {
  var isArchivePresented = false
  var isDetailPresented = false
  var selectedRoutineGroupID: Int64?

  mutating func presentArchive() {
    selectedRoutineGroupID = nil
    isDetailPresented = false
    isArchivePresented = true
  }

  mutating func presentDetail(routineGroupID: Int64) {
    guard routineGroupID > 0 else {
      return
    }
    selectedRoutineGroupID = routineGroupID
    isDetailPresented = true
  }

  mutating func reset() {
    isDetailPresented = false
    isArchivePresented = false
    selectedRoutineGroupID = nil
  }
}

@MainActor
@Observable
final class AccountRoutineGroupListViewModel {
  private let remoteService: (any AccountRoutineGroupRemoteServing)?
  private var currentMemberID: Int64?
  private var loadGeneration = 0
  private var requestTask: Task<[ServerRoutineGroupSummary], Error>?

  private(set) var state:
    AccountServerResourceState<[ServerRoutineGroupSummary]> = .signedOut
  private(set) var failureMessage: String?

  var isRemoteServiceAvailable: Bool {
    remoteService != nil
  }

  init(
    remoteService: (any AccountRoutineGroupRemoteServing)? = nil
  ) {
    self.remoteService = remoteService
  }

  func load(memberID: Int64?) async {
    let previousMemberID = currentMemberID
    invalidateRequest()
    currentMemberID = memberID

    guard let memberID, memberID > 0 else {
      state = .signedOut
      failureMessage = nil
      return
    }
    guard let remoteService else {
      state = .unavailable
      failureMessage = nil
      return
    }

    let previous = previousMemberID == memberID ? state.value : nil
    state = .loading(previous: previous)
    failureMessage = nil

    let generation = loadGeneration
    let request = Task {
      try await remoteService.fetchRoutineGroups(memberID: memberID)
    }
    requestTask = request
    defer {
      if generation == loadGeneration {
        requestTask = nil
      }
    }

    do {
      let summaries = try await withTaskCancellationHandler {
        try await request.value
      } onCancel: {
        request.cancel()
      }
      try Task.checkCancellation()
      guard generation == loadGeneration,
            currentMemberID == memberID else {
        return
      }

      state = summaries.isEmpty ? .empty : .content(summaries)
    } catch {
      guard generation == loadGeneration,
            currentMemberID == memberID,
            !isAccountRoutineGroupCancellation(error) else {
        return
      }

      state = .failed(
        previous: shouldDiscardAccountRoutineGroupPrevious(error)
          ? nil
          : previous
      )
      failureMessage = accountRoutineGroupFailureMessage(
        error,
        defaultMessage: "서버 루틴을 불러오지 못했어요."
      )
    }
  }

  func retry(memberID: Int64?) async {
    await load(memberID: memberID)
  }

  func accountDidChange(memberID: Int64?) {
    guard currentMemberID != memberID else {
      return
    }

    invalidateRequest()
    currentMemberID = memberID
    failureMessage = nil

    guard let memberID, memberID > 0 else {
      state = .signedOut
      return
    }
    state = remoteService == nil
      ? .unavailable
      : .loading(previous: nil)
  }

  private func invalidateRequest() {
    loadGeneration += 1
    requestTask?.cancel()
    requestTask = nil
  }
}

@MainActor
@Observable
final class AccountRoutineGroupDetailViewModel {
  private let remoteService: (any AccountRoutineGroupRemoteServing)?
  private var currentMemberID: Int64?
  private var currentRoutineGroupID: Int64?
  private var loadGeneration = 0
  private var requestTask: Task<ServerRoutineGroupDetail, Error>?

  private(set) var state:
    AccountServerResourceState<ServerRoutineGroupDetail> = .signedOut
  private(set) var failureMessage: String?

  init(
    remoteService: (any AccountRoutineGroupRemoteServing)? = nil
  ) {
    self.remoteService = remoteService
  }

  func load(
    routineGroupID: Int64,
    memberID: Int64?
  ) async {
    let previousMemberID = currentMemberID
    let previousRoutineGroupID = currentRoutineGroupID
    invalidateRequest()
    currentMemberID = memberID
    currentRoutineGroupID = routineGroupID

    guard let memberID, memberID > 0,
          routineGroupID > 0 else {
      state = .signedOut
      failureMessage = nil
      return
    }
    guard let remoteService else {
      state = .unavailable
      failureMessage = nil
      return
    }

    let preservesPrevious = previousMemberID == memberID
      && previousRoutineGroupID == routineGroupID
    let previous = preservesPrevious ? state.value : nil
    state = .loading(previous: previous)
    failureMessage = nil

    let generation = loadGeneration
    let request = Task {
      try await remoteService.fetchRoutineGroupDetail(
        routineGroupID: routineGroupID,
        memberID: memberID
      )
    }
    requestTask = request
    defer {
      if generation == loadGeneration {
        requestTask = nil
      }
    }

    do {
      let detail = try await withTaskCancellationHandler {
        try await request.value
      } onCancel: {
        request.cancel()
      }
      try Task.checkCancellation()
      guard generation == loadGeneration,
            currentMemberID == memberID,
            currentRoutineGroupID == routineGroupID else {
        return
      }

      state = .content(detail)
    } catch {
      guard generation == loadGeneration,
            currentMemberID == memberID,
            currentRoutineGroupID == routineGroupID,
            !isAccountRoutineGroupCancellation(error) else {
        return
      }

      state = .failed(
        previous: shouldDiscardAccountRoutineGroupPrevious(error)
          ? nil
          : previous
      )
      failureMessage = accountRoutineGroupDetailFailureMessage(error)
    }
  }

  func retry(
    routineGroupID: Int64,
    memberID: Int64?
  ) async {
    await load(
      routineGroupID: routineGroupID,
      memberID: memberID
    )
  }

  func accountDidChange(memberID: Int64?) {
    guard currentMemberID != memberID else {
      return
    }

    invalidateRequest()
    currentMemberID = memberID
    currentRoutineGroupID = nil
    failureMessage = nil

    guard let memberID, memberID > 0 else {
      state = .signedOut
      return
    }
    state = remoteService == nil
      ? .unavailable
      : .loading(previous: nil)
  }

  func screenDidDisappear() {
    invalidateRequest()
    currentRoutineGroupID = nil
    failureMessage = nil

    guard let currentMemberID, currentMemberID > 0 else {
      state = .signedOut
      return
    }
    state = remoteService == nil
      ? .unavailable
      : .loading(previous: nil)
  }

  private func invalidateRequest() {
    loadGeneration += 1
    requestTask?.cancel()
    requestTask = nil
  }
}

nonisolated private func isAccountRoutineGroupCancellation(
  _ error: any Error
) -> Bool {
  if error is CancellationError {
    return true
  }
  if let apiError = error as? APIError,
     apiError == .cancelled {
    return true
  }
  return false
}

nonisolated private func accountRoutineGroupDetailFailureMessage(
  _ error: any Error
) -> String {
  if let apiError = error as? APIError,
     case .server(let statusCode, _, _) = apiError,
     statusCode == 404 {
    return "삭제되었거나 접근할 수 없어요."
  }
  return accountRoutineGroupFailureMessage(
    error,
    defaultMessage: "서버 루틴 상세를 불러오지 못했어요."
  )
}

nonisolated private func accountRoutineGroupFailureMessage(
  _ error: any Error,
  defaultMessage: String
) -> String {
  if let apiError = error as? APIError {
    switch apiError {
    case .authenticationRequired:
      return "로그인이 만료됐어요. 다시 로그인해 주세요."
    case .server(let statusCode, _, _) where statusCode == 401:
      return "로그인이 만료됐어요. 다시 로그인해 주세요."
    case .invalidRequest,
         .capabilityDisabled,
         .transport,
         .server,
         .decoding,
         .missingResult,
         .cancelled:
      break
    }
  }
  if let remoteError = error as? AccountRoutineGroupRemoteError,
     remoteError == .accountAuthorizationChanged {
    return "계정이 변경되어 서버 루틴을 표시하지 않았어요."
  }
  return defaultMessage
}

nonisolated private func shouldDiscardAccountRoutineGroupPrevious(
  _ error: any Error
) -> Bool {
  if let apiError = error as? APIError,
     case .server(let statusCode, _, _) = apiError,
     statusCode == 404 {
    return true
  }
  if let remoteError = error as? AccountRoutineGroupRemoteError,
     remoteError == .accountAuthorizationChanged {
    return true
  }
  return false
}
