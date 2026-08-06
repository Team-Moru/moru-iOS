//
//  AccountRoutineGroupViewModels.swift
//  Moru
//

import Foundation
import Observation

nonisolated private enum AccountRoutineGroupActivationVerification:
  Equatable {
  case desired
  case undesired
  case unknown
}

nonisolated private struct PendingAccountRoutineGroupActivationVerification {
  let routineGroupID: Int64
  let desiredIsActive: Bool
  let memberID: Int64
}

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
  private var activityLoadGeneration = 0
  private var activeRequestTask: Task<ServerActiveRoutineGroup?, Error>?
  private var todayRequestTask: Task<ServerTodayRoutineProgress?, Error>?
  private var activationGeneration = 0
  private var activationRequestTask:
    Task<ServerRoutineGroupActivation, Error>?
  private var activationRefreshTask: Task<Void, Never>?
  private var pendingActivationVerification:
    PendingAccountRoutineGroupActivationVerification?

  private(set) var state:
    AccountServerResourceState<[ServerRoutineGroupSummary]> = .signedOut
  private(set) var failureMessage: String?
  private(set) var activeState:
    AccountServerResourceState<ServerActiveRoutineGroup> = .signedOut
  private(set) var todayState:
    AccountServerResourceState<ServerTodayRoutineProgress> = .signedOut
  private(set) var activeFailureMessage: String?
  private(set) var todayFailureMessage: String?
  private(set) var activatingRoutineGroupID: Int64?
  private(set) var activationFailureMessage: String?

  var isRemoteServiceAvailable: Bool {
    remoteService != nil
  }

  init(
    remoteService: (any AccountRoutineGroupRemoteServing)? = nil
  ) {
    self.remoteService = remoteService
  }

  func load(memberID: Int64?) async {
    await load(
      memberID: memberID,
      clearsActivationFailureOnSuccess: true
    )
  }

  private func load(
    memberID: Int64?,
    clearsActivationFailureOnSuccess: Bool
  ) async {
    guard !Task.isCancelled else {
      return
    }
    let didTransitionAccount = transitionAccountIfNeeded(to: memberID)
    invalidateRequest()

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

    let previous = didTransitionAccount ? nil : state.value
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
      if clearsActivationFailureOnSuccess {
        resolvePendingActivationUsingListIfPossible()
      }
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

  func loadActivity(memberID: Int64?) async {
    await loadActivity(
      memberID: memberID,
      resolvesPendingActivation: true
    )
  }

  private func loadActivity(
    memberID: Int64?,
    resolvesPendingActivation: Bool
  ) async {
    guard !Task.isCancelled else {
      return
    }
    let didTransitionAccount = transitionAccountIfNeeded(to: memberID)
    invalidateActivityRequests()

    guard let memberID, memberID > 0 else {
      activeState = .signedOut
      todayState = .signedOut
      activeFailureMessage = nil
      todayFailureMessage = nil
      return
    }
    guard let remoteService else {
      activeState = .unavailable
      todayState = .unavailable
      activeFailureMessage = nil
      todayFailureMessage = nil
      return
    }

    let preservesPrevious = !didTransitionAccount
    let previousActive = preservesPrevious ? activeState.value : nil
    let previousToday = preservesPrevious ? todayState.value : nil
    activeState = .loading(previous: previousActive)
    todayState = .loading(previous: previousToday)
    activeFailureMessage = nil
    todayFailureMessage = nil

    let generation = activityLoadGeneration
    let activeRequest = Task {
      try await remoteService.fetchActiveRoutineGroup(memberID: memberID)
    }
    let todayRequest = Task {
      try await remoteService.fetchTodayRoutineProgress(memberID: memberID)
    }
    activeRequestTask = activeRequest
    todayRequestTask = todayRequest

    await withTaskCancellationHandler {
      async let activeResolution: Void = resolveActiveRequest(
        activeRequest,
        memberID: memberID,
        generation: generation,
        previous: previousActive,
        resolvesPendingActivation: resolvesPendingActivation
      )
      async let todayResolution: Void = resolveTodayRequest(
        todayRequest,
        memberID: memberID,
        generation: generation,
        previous: previousToday
      )
      _ = await (activeResolution, todayResolution)
    } onCancel: {
      activeRequest.cancel()
      todayRequest.cancel()
    }

    guard generation == activityLoadGeneration else {
      return
    }
    activeRequestTask = nil
    todayRequestTask = nil
  }

  func retryActivity(memberID: Int64?) async {
    await loadActivity(memberID: memberID)
  }

  func updateActivation(
    routineGroupID: Int64,
    isActive: Bool,
    memberID: Int64?
  ) async {
    guard !Task.isCancelled,
          activationRequestTask == nil,
          routineGroupID > 0,
          let memberID,
          memberID > 0,
          memberID == currentMemberID,
          let remoteService else {
      return
    }

    activationGeneration += 1
    let generation = activationGeneration
    activatingRoutineGroupID = routineGroupID
    activationFailureMessage = nil
    pendingActivationVerification = nil

    let request = Task {
      try await remoteService.updateRoutineGroupActivation(
        routineGroupID: routineGroupID,
        isActive: isActive,
        memberID: memberID
      )
    }
    activationRequestTask = request
    defer {
      if generation == activationGeneration,
         currentMemberID == memberID {
        activationRequestTask = nil
        activatingRoutineGroupID = nil
      }
    }

    do {
      let activation = try await withTaskCancellationHandler {
        try await request.value
      } onCancel: {
        request.cancel()
      }
      try Task.checkCancellation()
      guard generation == activationGeneration,
            currentMemberID == memberID else {
        return
      }

      reconcileList(using: activation)
      reconcileActivityBeforeRefresh(using: activation)
      await refreshAfterActivation(
        memberID: memberID,
        generation: generation
      )
    } catch {
      guard generation == activationGeneration,
            currentMemberID == memberID,
            !isAccountRoutineGroupCancellation(error) else {
        return
      }

      guard requiresAccountRoutineGroupActivationVerification(error) else {
        activationFailureMessage = accountRoutineGroupFailureMessage(
          error,
          defaultMessage:
            "서버 루틴의 사용 상태를 변경하지 못했어요. 기존 상태를 유지해요."
        )
        return
      }

      activationFailureMessage =
        "사용 상태 변경 여부를 확인하지 못했어요. 서버 상태를 다시 확인해 주세요."
      let pendingVerification =
        PendingAccountRoutineGroupActivationVerification(
          routineGroupID: routineGroupID,
          desiredIsActive: isActive,
          memberID: memberID
        )
      pendingActivationVerification = pendingVerification
      await refreshAfterActivation(
        memberID: memberID,
        generation: generation
      )
      guard !Task.isCancelled,
            generation == activationGeneration,
            currentMemberID == memberID else {
        return
      }

      let verification = activationVerification(
        routineGroupID: routineGroupID,
        desiredIsActive: isActive
      )
      applyActivationVerification(
        verification,
        pending: pendingVerification
      )
    }
  }

  func accountDidChange(memberID: Int64?) {
    transitionAccountIfNeeded(to: memberID)
  }

  @discardableResult
  private func transitionAccountIfNeeded(to memberID: Int64?) -> Bool {
    guard currentMemberID != memberID else {
      return false
    }

    invalidateRequest()
    invalidateActivityRequests()
    invalidateActivationRequest()
    currentMemberID = memberID
    failureMessage = nil
    activeFailureMessage = nil
    todayFailureMessage = nil
    activationFailureMessage = nil

    guard let memberID, memberID > 0 else {
      state = .signedOut
      activeState = .signedOut
      todayState = .signedOut
      return true
    }
    if remoteService == nil {
      state = .unavailable
      activeState = .unavailable
      todayState = .unavailable
    } else {
      state = .loading(previous: nil)
      activeState = .loading(previous: nil)
      todayState = .loading(previous: nil)
    }
    return true
  }

  private func invalidateRequest() {
    loadGeneration += 1
    requestTask?.cancel()
    requestTask = nil
  }

  private func invalidateActivityRequests() {
    activityLoadGeneration += 1
    activeRequestTask?.cancel()
    todayRequestTask?.cancel()
    activeRequestTask = nil
    todayRequestTask = nil
  }

  private func invalidateActivationRequest() {
    activationGeneration += 1
    activationRequestTask?.cancel()
    activationRefreshTask?.cancel()
    activationRequestTask = nil
    activationRefreshTask = nil
    pendingActivationVerification = nil
    activatingRoutineGroupID = nil
  }

  private func refreshAfterActivation(
    memberID: Int64,
    generation: Int
  ) async {
    let refresh = Task { @MainActor [weak self] in
      guard let self,
            !Task.isCancelled,
            generation == self.activationGeneration,
            self.currentMemberID == memberID else {
        return
      }

      async let listReload: Void = self.load(
        memberID: memberID,
        clearsActivationFailureOnSuccess: false
      )
      async let activityReload: Void = self.loadActivity(
        memberID: memberID,
        resolvesPendingActivation: false
      )
      _ = await (listReload, activityReload)
    }
    activationRefreshTask = refresh

    await withTaskCancellationHandler {
      await refresh.value
    } onCancel: {
      refresh.cancel()
    }

    if generation == activationGeneration,
       currentMemberID == memberID {
      activationRefreshTask = nil
    }
  }

  private func activationVerification(
    routineGroupID: Int64,
    desiredIsActive: Bool
  ) -> AccountRoutineGroupActivationVerification {
    let listEvidence = listActivationVerification(
      routineGroupID: routineGroupID,
      desiredIsActive: desiredIsActive
    )
    let activeEvidence = activeActivationVerification(
      routineGroupID: routineGroupID,
      desiredIsActive: desiredIsActive
    )

    if listEvidence == .unknown {
      return activeEvidence
    }
    if activeEvidence == .unknown || activeEvidence == listEvidence {
      return listEvidence
    }
    return .unknown
  }

  private func listActivationVerification(
    routineGroupID: Int64,
    desiredIsActive: Bool
  ) -> AccountRoutineGroupActivationVerification {
    let summaries: [ServerRoutineGroupSummary]
    switch state {
    case .content(let value):
      summaries = value
    case .empty:
      return desiredIsActive ? .undesired : .desired
    case .signedOut, .unavailable, .loading, .failed:
      return .unknown
    }

    guard let summary = summaries.first(where: {
      $0.routineGroupID == routineGroupID
    }) else {
      return desiredIsActive ? .undesired : .desired
    }
    guard let isActive = summary.isActive else {
      return .unknown
    }
    return isActive == desiredIsActive ? .desired : .undesired
  }

  private func activeActivationVerification(
    routineGroupID: Int64,
    desiredIsActive: Bool
  ) -> AccountRoutineGroupActivationVerification {
    switch activeState {
    case .content(let activeRoutineGroup):
      let isTargetActive = activeRoutineGroup.routineGroupID
        == routineGroupID
      return isTargetActive == desiredIsActive ? .desired : .undesired
    case .empty:
      return desiredIsActive ? .undesired : .desired
    case .signedOut, .unavailable, .loading, .failed:
      return .unknown
    }
  }

  private func resolvePendingActivationUsingListIfPossible() {
    guard let pending = pendingActivationVerification else {
      activationFailureMessage = nil
      return
    }
    guard pending.memberID == currentMemberID else {
      pendingActivationVerification = nil
      activationFailureMessage = nil
      return
    }
    let verification = listActivationVerification(
      routineGroupID: pending.routineGroupID,
      desiredIsActive: pending.desiredIsActive
    )
    applyActivationVerification(verification, pending: pending)
  }

  private func resolvePendingActivationUsingActiveIfPossible() {
    guard let pending = pendingActivationVerification,
          pending.memberID == currentMemberID else {
      return
    }
    let verification = activeActivationVerification(
      routineGroupID: pending.routineGroupID,
      desiredIsActive: pending.desiredIsActive
    )
    applyActivationVerification(verification, pending: pending)
  }

  private func applyActivationVerification(
    _ verification: AccountRoutineGroupActivationVerification,
    pending: PendingAccountRoutineGroupActivationVerification
  ) {
    guard pending.memberID == currentMemberID else {
      return
    }

    switch verification {
    case .desired:
      reconcileList(
        using: ServerRoutineGroupActivation(
          routineGroupID: pending.routineGroupID,
          isActive: pending.desiredIsActive
        )
      )
      activationFailureMessage = nil
      pendingActivationVerification = nil
    case .undesired:
      reconcileList(
        using: ServerRoutineGroupActivation(
          routineGroupID: pending.routineGroupID,
          isActive: !pending.desiredIsActive
        )
      )
      activationFailureMessage =
        "요청한 사용 상태가 서버에 반영되지 않았어요."
      pendingActivationVerification = nil
    case .unknown:
      activationFailureMessage =
        "사용 상태 변경 여부를 확인하지 못했어요. 다시 확인해 주세요."
      pendingActivationVerification = pending
    }
  }

  private func resolveActiveRequest(
    _ request: Task<ServerActiveRoutineGroup?, Error>,
    memberID: Int64,
    generation: Int,
    previous: ServerActiveRoutineGroup?,
    resolvesPendingActivation: Bool
  ) async {
    do {
      let activeRoutineGroup = try await request.value
      try Task.checkCancellation()
      guard generation == activityLoadGeneration,
            currentMemberID == memberID else {
        return
      }

      activeState = activeRoutineGroup.map {
        .content($0)
      } ?? .empty
      activeFailureMessage = nil
      if resolvesPendingActivation {
        resolvePendingActivationUsingActiveIfPossible()
      }
    } catch {
      guard generation == activityLoadGeneration,
            currentMemberID == memberID,
            !isAccountRoutineGroupCancellation(error) else {
        return
      }

      activeState = .failed(
        previous: shouldDiscardAccountRoutineGroupPrevious(error)
          ? nil
          : previous
      )
      activeFailureMessage = accountRoutineGroupFailureMessage(
        error,
        defaultMessage: "사용 중인 서버 루틴을 불러오지 못했어요."
      )
    }
  }

  private func resolveTodayRequest(
    _ request: Task<ServerTodayRoutineProgress?, Error>,
    memberID: Int64,
    generation: Int,
    previous: ServerTodayRoutineProgress?
  ) async {
    do {
      let progress = try await request.value
      try Task.checkCancellation()
      guard generation == activityLoadGeneration,
            currentMemberID == memberID else {
        return
      }

      todayState = progress.map {
        .content($0)
      } ?? .empty
      todayFailureMessage = nil
    } catch {
      guard generation == activityLoadGeneration,
            currentMemberID == memberID,
            !isAccountRoutineGroupCancellation(error) else {
        return
      }

      todayState = .failed(
        previous: shouldDiscardAccountRoutineGroupPrevious(error)
          ? nil
          : previous
      )
      todayFailureMessage = accountRoutineGroupFailureMessage(
        error,
        defaultMessage: "오늘의 서버 루틴 현황을 불러오지 못했어요."
      )
    }
  }

  private func reconcileList(using activation: ServerRoutineGroupActivation) {
    func reconciled(
      _ summaries: [ServerRoutineGroupSummary]?
    ) -> [ServerRoutineGroupSummary]? {
      summaries?.map { summary in
        let nextIsActive: Bool?
        if summary.routineGroupID == activation.routineGroupID {
          nextIsActive = activation.isActive
        } else if activation.isActive {
          nextIsActive = false
        } else {
          nextIsActive = summary.isActive
        }

        return ServerRoutineGroupSummary(
          routineGroupID: summary.routineGroupID,
          title: summary.title,
          isActive: nextIsActive,
          routineCount: summary.routineCount,
          totalDurationSeconds: summary.totalDurationSeconds
        )
      }
    }

    switch state {
    case .content(let summaries):
      state = .content(reconciled(summaries) ?? [])
    case .loading(let previous):
      state = .loading(previous: reconciled(previous))
    case .failed(let previous):
      state = .failed(previous: reconciled(previous))
    case .unavailable, .signedOut, .empty:
      break
    }
  }

  private func reconcileActivityBeforeRefresh(
    using activation: ServerRoutineGroupActivation
  ) {
    let activeRoutineGroup = activeState.value
    let todayProgress = todayState.value

    if activation.isActive {
      let preservesCurrent = activeRoutineGroup?.routineGroupID
        == activation.routineGroupID
      activeState = .loading(
        previous: preservesCurrent ? activeRoutineGroup : nil
      )
      todayState = .loading(
        previous: preservesCurrent ? todayProgress : nil
      )
    } else if activeRoutineGroup?.routineGroupID
      == activation.routineGroupID {
      activeState = .empty
      todayState = .empty
    }
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

nonisolated private func requiresAccountRoutineGroupActivationVerification(
  _ error: any Error
) -> Bool {
  if let apiError = error as? APIError {
    switch apiError {
    case .transport, .decoding, .missingResult:
      return true
    case .server(let statusCode, _, _):
      return statusCode == 408
        || statusCode == 429
        || statusCode == 404
        || statusCode == 410
        || !(400..<500).contains(statusCode)
    case .invalidRequest,
         .authenticationRequired,
         .capabilityDisabled,
         .cancelled:
      return false
    }
  }
  if let remoteError = error as? AccountRoutineGroupRemoteError {
    return remoteError == .invalidResponse
  }
  return true
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
