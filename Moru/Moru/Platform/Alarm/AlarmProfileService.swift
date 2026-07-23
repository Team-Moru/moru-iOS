//
//  AlarmProfileService.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

@MainActor
final class AlarmProfileService: ProfileAlarmServicing {
  private let primaryScheduler: any AlarmScheduling
  private let fallbackScheduler: any AlarmScheduling
  private let stateRepository: any AlarmPlatformStateRepository
  private let mutationCoordinator: any AlarmScheduleMutating

  init(
    primaryScheduler: any AlarmScheduling,
    fallbackScheduler: any AlarmScheduling,
    stateRepository: any AlarmPlatformStateRepository,
    mutationCoordinator: any AlarmScheduleMutating
  ) {
    self.primaryScheduler = primaryScheduler
    self.fallbackScheduler = fallbackScheduler
    self.stateRepository = stateRepository
    self.mutationCoordinator = mutationCoordinator
  }

  func currentStatus() async -> ProfileAlarmStatus {
    if let records = try? stateRepository.fetchRecords(),
       records.contains(where: { $0.state == .repairRequired }) {
      return .repairRequired
    }

    let primaryState = await primaryScheduler.authorizationState()
    if primaryState == .authorized {
      return .configured
    }
    if primaryState == .notDetermined {
      return .permissionNotDetermined
    }

    let fallbackState = await fallbackScheduler.authorizationState()
    switch fallbackState {
    case .authorized:
      return .fallbackConfigured
    case .notDetermined:
      return .permissionNotDetermined
    case .denied:
      return .permissionOff
    case .unavailable:
      return primaryState == .denied ? .permissionOff : .unavailable
    }
  }

  func requestAuthorization() async -> ProfileAlarmStatus {
    let primaryState = await resolvedAuthorization(for: primaryScheduler)
    if primaryState != .authorized {
      _ = await resolvedAuthorization(for: fallbackScheduler)
    }
    await mutationCoordinator.reconcile()
    return await currentStatus()
  }

  func retryScheduling() async -> ProfileAlarmStatus {
    await mutationCoordinator.reconcile()
    return await currentStatus()
  }

  func cancelAllAlarms() async throws {
    try await mutationCoordinator.cancelAllForReset()
  }

  private func resolvedAuthorization(
    for scheduler: any AlarmScheduling
  ) async -> AlarmAuthorizationState {
    let state = await scheduler.authorizationState()
    guard state == .notDetermined else {
      return state
    }

    return (try? await scheduler.requestAuthorization()) ?? .unavailable
  }
}
