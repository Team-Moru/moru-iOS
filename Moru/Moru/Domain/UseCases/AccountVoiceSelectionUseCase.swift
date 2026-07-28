//
//  AccountVoiceSelectionUseCase.swift
//  Moru
//

import Foundation

nonisolated enum VoiceSelectionServerDisposition: Equatable, Sendable {
  case notApplicable
  case queued
  case queueFailed
}

struct VoiceSelectionCommitResult: Equatable {
  let profileResult: ProfileSettingsLoadResult
  let serverDisposition: VoiceSelectionServerDisposition
}

nonisolated enum AccountVoiceMismatchChoice: Equatable, Sendable {
  case keepDevice
  case useServer
}

@MainActor
protocol AccountVoiceSelectionUseCaseProtocol: AnyObject {
  func loadCatalogue() async -> AccountVoiceCatalogueSnapshot
  func select(_ option: AccountVoiceOption) async throws -> VoiceSelectionCommitResult
  func resolveMismatch(
    _ mismatch: AccountVoiceMismatch,
    choice: AccountVoiceMismatchChoice
  ) async throws -> VoiceSelectionCommitResult
}

@MainActor
final class AccountVoiceSelectionUseCase: AccountVoiceSelectionUseCaseProtocol {
  private let profileSettingsUseCase: any ProfileSettingsUseCaseProtocol
  private let voiceAvailabilityProbe: any VoiceAvailabilityProbing
  private let remoteService: any AccountVoiceRemoteServing
  private let catalogueRepository: any ServerVoiceCatalogRepository
  private let mutationRepository: any ServerMutationRepository
  private let serverSynchronizer: any ServerSynchronizing
  private let signedInMemberProvider: any SignedInMemberProviding
  private let compatibilityTable: VoiceCompatibilityTable
  private let now: () -> Date

  init(
    profileSettingsUseCase: any ProfileSettingsUseCaseProtocol,
    voiceAvailabilityProbe: any VoiceAvailabilityProbing,
    remoteService: any AccountVoiceRemoteServing,
    catalogueRepository: any ServerVoiceCatalogRepository,
    mutationRepository: any ServerMutationRepository,
    serverSynchronizer: any ServerSynchronizing,
    signedInMemberProvider: any SignedInMemberProviding,
    compatibilityTable: VoiceCompatibilityTable = .production,
    now: @escaping () -> Date = Date.init
  ) {
    self.profileSettingsUseCase = profileSettingsUseCase
    self.voiceAvailabilityProbe = voiceAvailabilityProbe
    self.remoteService = remoteService
    self.catalogueRepository = catalogueRepository
    self.mutationRepository = mutationRepository
    self.serverSynchronizer = serverSynchronizer
    self.signedInMemberProvider = signedInMemberProvider
    self.compatibilityTable = compatibilityTable
    self.now = now
  }

  func loadCatalogue() async -> AccountVoiceCatalogueSnapshot {
    guard let memberID = signedInMemberProvider.signedInMemberID else {
      return bundledFallbackSnapshot(notice: nil)
    }

    var notice: String?

    do {
      let voices = try await remoteService.fetchVoices(memberID: memberID)
      try catalogueRepository.replaceCatalog(
        try makeCatalogEntries(voices, memberID: memberID),
        memberID: memberID
      )
    } catch {
      notice = "서버 음성 목록을 불러오지 못해 저장된 목록을 사용해요."
    }

    guard signedInMemberProvider.signedInMemberID == memberID else {
      return bundledFallbackSnapshot(notice: nil)
    }

    let entries = (try? catalogueRepository.catalog(memberID: memberID)) ?? []
    guard !entries.isEmpty else {
      return bundledFallbackSnapshot(
        notice: "서버 음성 목록을 사용할 수 없어 앱 내장 음성을 표시해요."
      )
    }

    let serverOptions = entries.map(makeServerOption)
    let options = mergedOptions(serverOptions: serverOptions)
    let localVoice = try? profileSettingsUseCase.loadProfileSettings().profile.selectedVoice
    let authoritative = serverOptions.first(
      where: \.isAuthoritativeServerSelection
    )
    let mismatch: AccountVoiceMismatch?
    if let localVoice,
       let authoritative,
       authoritative.localVoice?.id != localVoice.id {
      mismatch = AccountVoiceMismatch(
        localVoice: localVoice,
        serverVoice: authoritative
      )
    } else {
      mismatch = nil
    }

    return AccountVoiceCatalogueSnapshot(
      options: options,
      mismatch: mismatch,
      notice: notice
    )
  }

  func select(_ option: AccountVoiceOption) async throws -> VoiceSelectionCommitResult {
    guard option.availability.isSelectable,
          let localVoice = option.localVoice else {
      throw ProfileSettingsUseCaseError.unavailableVoice(option.id)
    }

    if option.source == .serverCatalogue,
       let memberID = signedInMemberProvider.signedInMemberID,
       option.serverMemberID != memberID {
      throw ProfileSettingsUseCaseError.unavailableVoice(option.id)
    }

    let localResult = try profileSettingsUseCase.selectVoice(localVoice)
    guard let memberID = signedInMemberProvider.signedInMemberID,
          option.source == .serverCatalogue,
          option.serverMemberID == memberID,
          let ttsID = option.serverTtsID,
          let voiceCode = option.serverVoiceCode else {
      return VoiceSelectionCommitResult(
        profileResult: localResult,
        serverDisposition: .notApplicable
      )
    }

    do {
      let payload = VoiceSelectionMutationPayload(
        memberID: memberID,
        ttsID: ttsID,
        voiceCode: VoiceCompatibilityTable.normalizedServerVoiceCode(voiceCode),
        localVoiceID: localVoice.id
      )
      _ = try mutationRepository.enqueue(
        EnqueuedServerMutation(
          memberID: memberID,
          operation: .replaceVoiceSelection,
          operationKey: VoiceSelectionMutationPayload.operationKey,
          payload: try payload.encoded()
        )
      )
    } catch {
      return VoiceSelectionCommitResult(
        profileResult: localResult,
        serverDisposition: .queueFailed
      )
    }

    await serverSynchronizer.synchronize(
      memberID: memberID,
      trigger: .manual
    )
    return VoiceSelectionCommitResult(
      profileResult: localResult,
      serverDisposition: .queued
    )
  }

  func resolveMismatch(
    _ mismatch: AccountVoiceMismatch,
    choice: AccountVoiceMismatchChoice
  ) async throws -> VoiceSelectionCommitResult {
    switch choice {
    case .useServer:
      return try await select(mismatch.serverVoice)
    case .keepDevice:
      let snapshot = await loadCatalogue()
      guard let deviceOption = snapshot.options.first(where: {
        $0.localVoice?.id == mismatch.localVoice.id
          && $0.availability.isSelectable
      }) else {
        throw ProfileSettingsUseCaseError.unavailableVoice(
          mismatch.localVoice.id
        )
      }
      let result = try await select(deviceOption)
      guard deviceOption.source == .bundledFallback else {
        return result
      }
      guard let memberID = mismatch.serverVoice.serverMemberID,
            signedInMemberProvider.signedInMemberID == memberID else {
        throw ProfileSettingsUseCaseError.unavailableVoice(
          mismatch.serverVoice.id
        )
      }

      try catalogueRepository.clearAuthoritativeSelection(
        memberID: memberID
      )
      return result
    }
  }

  private func makeCatalogEntries(
    _ voices: [ServerVoiceCatalogueItem],
    memberID: Int64
  ) throws -> [ServerVoiceCatalogEntry] {
    let existing = (try? catalogueRepository.catalog(memberID: memberID)) ?? []
    let selectedEntry = existing.first {
      VoiceCatalogMetadata.decode(rawValue: $0.tierRawValue)?
        .isAuthoritativeSelection == true
    }
    let selectedMetadata = selectedEntry.flatMap {
      VoiceCatalogMetadata.decode(rawValue: $0.tierRawValue)
    }
    let selectedVoiceCode = selectedEntry.map {
      VoiceCompatibilityTable.normalizedServerVoiceCode($0.voiceCode)
    }
    let fetchedAt = now()

    var entries = try voices.map { voice in
      let voiceCode = VoiceCompatibilityTable.normalizedServerVoiceCode(
        voice.voiceCode
      )
      let localVoice = localVoice(forServerVoiceCode: voiceCode)
      let metadata = VoiceCatalogMetadata(
        ttsID: voice.ttsID,
        proOnly: voice.proOnly,
        description: voice.description,
        isAuthoritativeSelection: selectedVoiceCode == voiceCode
      )

      return ServerVoiceCatalogEntry(
        memberID: memberID,
        voiceCode: voiceCode,
        displayName: voice.displayName,
        tierRawValue: try metadata.encodedRawValue(),
        isLocallyPlayable: localVoice.map(voiceAvailabilityProbe.isAvailable) ?? false,
        fetchedAt: fetchedAt
      )
    }

    if let selectedEntry,
       let selectedMetadata,
       let selectedVoiceCode,
       !entries.contains(where: {
         $0.voiceCode == selectedVoiceCode
       }) {
      entries.append(
        ServerVoiceCatalogEntry(
          id: selectedEntry.id,
          memberID: memberID,
          voiceCode: selectedEntry.voiceCode,
          displayName: selectedEntry.displayName,
          tierRawValue: try VoiceCatalogMetadata(
            ttsID: selectedMetadata.ttsID,
            proOnly: selectedMetadata.proOnly,
            description: selectedMetadata.description,
            isAuthoritativeSelection: true,
            isCatalogueListed: false
          ).encodedRawValue(),
          isLocallyPlayable: false,
          fetchedAt: fetchedAt
        )
      )
    }

    return entries
  }

  private func makeServerOption(
    _ entry: ServerVoiceCatalogEntry
  ) -> AccountVoiceOption {
    guard let metadata = VoiceCatalogMetadata.decode(
      rawValue: entry.tierRawValue
    ) else {
      return AccountVoiceOption(
        id: "server.\(entry.voiceCode)",
        serverMemberID: entry.memberID,
        serverVoiceCode: entry.voiceCode,
        serverTtsID: nil,
        displayName: entry.displayName,
        detail: "지원하지 않는 서버 음성 정보",
        localVoice: nil,
        availability: .unknownMetadata,
        source: .serverCatalogue,
        isAuthoritativeServerSelection: false
      )
    }

    let localVoice = localVoice(forServerVoiceCode: entry.voiceCode)
    let availability: AccountVoiceAvailability
    let detail: String
    if !metadata.isListedInCatalogue {
      availability = .notInCatalogue
      detail = "현재 서버 음성 목록에서 제공되지 않아요"
    } else if metadata.proOnly {
      availability = .proOnly
      detail = "PRO 전용 · 아직 선택할 수 없어요"
    } else if localVoice == nil {
      availability = .incompatible
      detail = "앱 내장 음성과 호환되지 않아요"
    } else if !entry.isLocallyPlayable {
      availability = .missingBundledAudio
      detail = "앱 내장 음성 파일이 없어요"
    } else {
      availability = .selectable
      detail = metadata.description ?? "앱 내장 음성과 호환됨"
    }

    return AccountVoiceOption(
      id: "server.\(metadata.ttsID).\(entry.voiceCode)",
      serverMemberID: entry.memberID,
      serverVoiceCode: entry.voiceCode,
      serverTtsID: metadata.ttsID,
      displayName: entry.displayName,
      detail: detail,
      localVoice: localVoice,
      availability: availability,
      source: .serverCatalogue,
      isAuthoritativeServerSelection: metadata.isAuthoritativeSelection
    )
  }

  private func bundledFallbackSnapshot(
    notice: String?
  ) -> AccountVoiceCatalogueSnapshot {
    AccountVoiceCatalogueSnapshot(
      options: bundledOptions(),
      mismatch: nil,
      notice: notice
    )
  }

  private func mergedOptions(
    serverOptions: [AccountVoiceOption]
  ) -> [AccountVoiceOption] {
    let selectableServerOptions = serverOptions.filter {
      $0.availability.isSelectable
    }
    let representedLocalVoiceIDs = Set(
      selectableServerOptions.compactMap(\.localVoice?.id)
    )
    let unrepresentedBundledOptions = bundledOptions().filter {
      guard let localVoiceID = $0.localVoice?.id else {
        return true
      }
      return !representedLocalVoiceIDs.contains(localVoiceID)
    }
    let unavailableServerOptions = serverOptions.filter {
      !$0.availability.isSelectable
    }

    return selectableServerOptions
      + unrepresentedBundledOptions
      + unavailableServerOptions
  }

  private func bundledOptions() -> [AccountVoiceOption] {
    VoiceProfile.localVoices.map { voice in
      let isAvailable = voiceAvailabilityProbe.isAvailable(voice)
      return AccountVoiceOption(
        id: "bundled.\(voice.id)",
        serverMemberID: nil,
        serverVoiceCode: nil,
        serverTtsID: nil,
        displayName: voice.displayName,
        detail: isAvailable ? "앱 내장 음성" : "음성 파일 없음",
        localVoice: voice,
        availability: isAvailable ? .selectable : .missingBundledAudio,
        source: .bundledFallback,
        isAuthoritativeServerSelection: false
      )
    }
  }

  private func localVoice(forServerVoiceCode voiceCode: String) -> VoiceProfile? {
    guard let localVoiceID = compatibilityTable.localVoiceID(
      forServerVoiceCode: voiceCode
    ) else {
      return nil
    }
    return VoiceProfile.localVoices.first { $0.id == localVoiceID }
  }
}

@MainActor
final class UnavailableAccountVoiceSelectionUseCase:
  AccountVoiceSelectionUseCaseProtocol {
  private let profileSettingsUseCase: any ProfileSettingsUseCaseProtocol
  private let voiceAvailabilityProbe: any VoiceAvailabilityProbing

  init(
    profileSettingsUseCase: any ProfileSettingsUseCaseProtocol,
    voiceAvailabilityProbe: any VoiceAvailabilityProbing
  ) {
    self.profileSettingsUseCase = profileSettingsUseCase
    self.voiceAvailabilityProbe = voiceAvailabilityProbe
  }

  func loadCatalogue() async -> AccountVoiceCatalogueSnapshot {
    AccountVoiceCatalogueSnapshot(
      options: VoiceProfile.localVoices.map { voice in
        let available = voiceAvailabilityProbe.isAvailable(voice)
        return AccountVoiceOption(
          id: "bundled.\(voice.id)",
          serverMemberID: nil,
          serverVoiceCode: nil,
          serverTtsID: nil,
          displayName: voice.displayName,
          detail: available ? "앱 내장 음성" : "음성 파일 없음",
          localVoice: voice,
          availability: available ? .selectable : .missingBundledAudio,
          source: .bundledFallback,
          isAuthoritativeServerSelection: false
        )
      },
      mismatch: nil,
      notice: nil
    )
  }

  func select(_ option: AccountVoiceOption) async throws -> VoiceSelectionCommitResult {
    guard option.availability.isSelectable,
          let voice = option.localVoice else {
      throw ProfileSettingsUseCaseError.unavailableVoice(option.id)
    }
    return VoiceSelectionCommitResult(
      profileResult: try profileSettingsUseCase.selectVoice(voice),
      serverDisposition: .notApplicable
    )
  }

  func resolveMismatch(
    _ mismatch: AccountVoiceMismatch,
    choice: AccountVoiceMismatchChoice
  ) async throws -> VoiceSelectionCommitResult {
    let voice = choice == .useServer
      ? mismatch.serverVoice.localVoice
      : mismatch.localVoice
    guard let voice else {
      throw ProfileSettingsUseCaseError.unavailableVoice(
        mismatch.serverVoice.id
      )
    }
    return VoiceSelectionCommitResult(
      profileResult: try profileSettingsUseCase.selectVoice(voice),
      serverDisposition: .notApplicable
    )
  }
}
