//
//  RoutineTTSBindingValidator.swift
//  Moru
//

import Foundation

/// 준비해 둔 오디오가 **지금도 그 루틴의 것인지** 판단한다.
///
/// 로컬 루틴과 서버 루틴은 `RoutineServerBinding`으로 이어진다. 이 연결이
/// 끊기거나 다른 계정/네임스페이스의 것으로 바뀌면, 캐시해 둔 오디오는 남의
/// 루틴 음성이 된다. 그래서 재생 직전에 매번 다시 확인한다.
///
/// `RoutineTTSWarmupCoordinator`에서 떼어냈다. 이 여덟 개 함수는 코디네이터의
/// 가변 상태를 하나도 건드리지 않고 동기화 저장소만 읽는다. 붙어 있을 이유가
/// 없었고, 떨어져 나오니 코디네이터를 띄우지 않고도 규칙을 시험할 수 있다.
@MainActor
struct RoutineTTSBindingValidator {
  /// 준비된 오디오의 바인딩 검증 결과.
  enum Validation {
    case valid
    case invalid
    /// 저장소 읽기가 실패했다. 바인딩이 틀렸다는 뜻이 아니므로 버리지 않는다.
    case unavailable
  }

  private let bindingRepository: any RoutineSyncRepository
  private let serverNamespace: RoutineSyncServerNamespace

  init(
    bindingRepository: any RoutineSyncRepository,
    serverNamespace: RoutineSyncServerNamespace
  ) {
    self.bindingRepository = bindingRepository
    self.serverNamespace = serverNamespace
  }

  // MARK: - 서버 생성 의도

  func hasPendingGroupBinding(
    memberID: Int64,
    routineGroupLocalID: UUID
  ) throws -> Bool {
    guard let mutation = try bindingRepository.mutation(
      memberID: memberID,
      operation: .createRoutineGroup,
      entityKind: .routineGroup,
      localEntityID: routineGroupLocalID
    ) else {
      return false
    }

    return Self.isDeliveryPending(mutation.state)
  }

  func hasServerSyncIntent(
    memberID: Int64,
    routineGroupLocalID: UUID,
    routineLocalID: UUID
  ) throws -> Bool {
    if try bindingRepository.mutation(
      memberID: memberID,
      operation: .createRoutineGroup,
      entityKind: .routineGroup,
      localEntityID: routineGroupLocalID
    ) != nil {
      return true
    }

    if try bindingRepository.mutation(
      memberID: memberID,
      operation: .addRoutine,
      entityKind: .routine,
      localEntityID: routineLocalID
    ) != nil {
      return true
    }

    return try bindingRepository.binding(
      memberID: memberID,
      entityKind: .routine,
      localEntityID: routineLocalID
    ) != nil
  }

  func hasPendingRoutineBinding(
    memberID: Int64,
    routineGroupLocalID: UUID,
    routineLocalID: UUID
  ) throws -> Bool {
    if try hasPendingGroupBinding(
      memberID: memberID,
      routineGroupLocalID: routineGroupLocalID
    ) {
      return true
    }

    guard let mutation = try bindingRepository.mutation(
      memberID: memberID,
      operation: .addRoutine,
      entityKind: .routine,
      localEntityID: routineLocalID
    ) else {
      return false
    }

    return Self.isDeliveryPending(mutation.state)
  }

  /// 아직 서버 응답을 기다릴 만한 상태인가.
  static func isDeliveryPending(_ state: RoutineSyncMutationState) -> Bool {
    switch state {
    // Newly saved groups start waiting for runtime contract admission, then
    // become queued. All three states can still gain a server binding during
    // the same bounded first-cue window, so none should fall through
    // silently. `needsReconciliation` means the request may already have
    // reached the server; `RoutineSyncSender` retries it automatically
    // (see its `pendingReplay` branch), so it is not a dead end either.
    case .waitingForServerContract, .queued, .attempting, .needsReconciliation:
      true
    // `blocked` is the only state that requires explicit intervention and
    // will never resolve on its own.
    case .blocked:
      false
    }
  }

  // MARK: - 준비된 오디오의 바인딩 재확인

  func validateCurrentBinding(
    routineGroupLocalID: UUID,
    routineLocalID: UUID,
    expectedGroupRemoteID: Int64,
    expectedRoutineRemoteID: Int64,
    identity: AccountSessionIdentity
  ) -> Validation {
    do {
      guard let groupBinding = try bindingRepository.binding(
        memberID: identity.memberID,
        entityKind: .routineGroup,
        localEntityID: routineGroupLocalID
      ), let routineBinding = try bindingRepository.binding(
        memberID: identity.memberID,
        entityKind: .routine,
        localEntityID: routineLocalID
      ) else {
        return .invalid
      }

      guard isValidGroupBinding(
        groupBinding,
        routineGroupLocalID: routineGroupLocalID,
        identity: identity
      ), groupBinding.remoteID == expectedGroupRemoteID,
      isValidRoutineBinding(
        routineBinding,
        routineGroupLocalID: routineGroupLocalID,
        routineLocalID: routineLocalID,
        groupBinding: groupBinding,
        identity: identity
      ), routineBinding.remoteID == expectedRoutineRemoteID else {
        return .invalid
      }

      return .valid
    } catch {
      return .unavailable
    }
  }

  /// 그룹 바인딩 한 건이 이 계정·네임스페이스의 것인지.
  func isValidGroupBinding(
    _ binding: RoutineServerBinding,
    routineGroupLocalID: UUID,
    identity: AccountSessionIdentity
  ) -> Bool {
    binding.entityKind == .routineGroup
      && binding.localEntityID == routineGroupLocalID
      && binding.remoteID > 0
      && binding.memberID == identity.memberID
      && binding.serverNamespace == serverNamespace
  }

  /// 루틴 바인딩 한 건이 위 그룹 바인딩과 짝이 맞는지.
  func isValidRoutineBinding(
    _ binding: RoutineServerBinding,
    routineGroupLocalID: UUID,
    routineLocalID: UUID,
    groupBinding: RoutineServerBinding,
    identity: AccountSessionIdentity
  ) -> Bool {
    binding.entityKind == .routine
      && binding.localEntityID == routineLocalID
      && binding.remoteID > 0
      && binding.memberID == identity.memberID
      && binding.serverNamespace == serverNamespace
      && binding.parentEntityKind == .routineGroup
      && binding.parentLocalEntityID == routineGroupLocalID
      && binding.memberID == groupBinding.memberID
      && binding.serverNamespace == groupBinding.serverNamespace
  }
}
