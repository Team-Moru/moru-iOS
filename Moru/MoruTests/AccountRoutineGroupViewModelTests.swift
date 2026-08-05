//
//  AccountRoutineGroupViewModelTests.swift
//  MoruTests
//

import XCTest

@testable import Moru

final class AccountRoutineGroupViewModelTests: XCTestCase {
  @MainActor
  func testArchiveDoesNotRequestUntilListLoadStarts() async {
    let service = AccountRoutineGroupRemoteStub(
      listResults: [.success([routineGroupSummary(id: 1)])],
      detailResults: [.success(routineGroupDetail(id: 1))]
    )
    let listViewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )
    let detailViewModel = AccountRoutineGroupDetailViewModel(
      remoteService: service
    )

    listViewModel.accountDidChange(memberID: 98)

    let initialCalls = await service.calls
    XCTAssertEqual(initialCalls, [])
    XCTAssertEqual(listViewModel.state, .loading(previous: nil))
    XCTAssertEqual(detailViewModel.state, .signedOut)

    await listViewModel.load(memberID: 98)

    let calls = await service.calls
    XCTAssertEqual(calls, [.list(memberID: 98)])
    XCTAssertEqual(
      listViewModel.state,
      .content([routineGroupSummary(id: 1)])
    )
  }

  @MainActor
  func testListPreservesServerOrderAndEqualTitles() async {
    let summaries = [
      routineGroupSummary(id: 7, title: "같은 이름"),
      routineGroupSummary(id: 3, title: "같은 이름"),
    ]
    let service = AccountRoutineGroupRemoteStub(
      listResults: [.success(summaries)]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )

    await viewModel.load(memberID: 98)

    XCTAssertEqual(viewModel.state, .content(summaries))
  }

  @MainActor
  func testEmptyListHasDistinctEmptyState() async {
    let service = AccountRoutineGroupRemoteStub(
      listResults: [.success([])]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )

    await viewModel.load(memberID: 98)

    XCTAssertEqual(viewModel.state, .empty)
    XCTAssertNil(viewModel.failureMessage)
  }

  @MainActor
  func testFailedListRefreshKeepsSameMembersPreviousValues() async {
    let previous = [routineGroupSummary(id: 1)]
    let service = AccountRoutineGroupRemoteStub(
      listResults: [
        .success(previous),
        .failure(.unavailable),
      ]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )

    await viewModel.load(memberID: 98)
    await viewModel.load(memberID: 98)

    XCTAssertEqual(viewModel.state, .failed(previous: previous))
    XCTAssertEqual(
      viewModel.failureMessage,
      "서버 루틴을 불러오지 못했어요."
    )
  }

  @MainActor
  func testListNeverPublishesOldAccountResponseAfterLogout() async {
    let service = DeferredAccountRoutineGroupRemoteStub()
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )

    let load = Task {
      await viewModel.load(memberID: 98)
    }
    await service.waitUntilListRequested()

    viewModel.accountDidChange(memberID: nil)
    await service.resumeList(
      returning: [routineGroupSummary(id: 98)]
    )
    await load.value

    XCTAssertEqual(viewModel.state, .signedOut)
    XCTAssertNil(viewModel.failureMessage)
  }

  @MainActor
  func testListCancellationDoesNotPublishFailure() async {
    let service = AccountRoutineGroupRemoteStub(
      listResults: [.failure(.cancelled)]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )

    await viewModel.load(memberID: 98)

    XCTAssertEqual(viewModel.state, .loading(previous: nil))
    XCTAssertNil(viewModel.failureMessage)
  }

  @MainActor
  func testMissingServiceAndSignedOutHaveDistinctStates() async {
    let viewModel = AccountRoutineGroupListViewModel()

    await viewModel.load(memberID: 98)
    XCTAssertEqual(viewModel.state, .unavailable)
    XCTAssertFalse(viewModel.isRemoteServiceAvailable)

    await viewModel.load(memberID: nil)
    XCTAssertEqual(viewModel.state, .signedOut)
  }

  @MainActor
  func testDetailRequestStartsOnlyWhenDetailLoadStarts() async {
    let detail = routineGroupDetail(id: 12)
    let service = AccountRoutineGroupRemoteStub(
      detailResults: [.success(detail)]
    )
    let viewModel = AccountRoutineGroupDetailViewModel(
      remoteService: service
    )

    let initialCalls = await service.calls
    XCTAssertEqual(initialCalls, [])

    await viewModel.load(routineGroupID: 12, memberID: 98)

    let calls = await service.calls
    XCTAssertEqual(
      calls,
      [.detail(routineGroupID: 12, memberID: 98)]
    )
    XCTAssertEqual(viewModel.state, .content(detail))
  }

  @MainActor
  func testDetail404HasFriendlyMessage() async {
    let service = AccountRoutineGroupRemoteStub(
      detailResults: [
        .failure(
          .api(
            .server(
              statusCode: 404,
              code: "ROUTINE_GROUP404",
              message: "not found"
            )
          )
        ),
      ]
    )
    let viewModel = AccountRoutineGroupDetailViewModel(
      remoteService: service
    )

    await viewModel.load(routineGroupID: 12, memberID: 98)

    XCTAssertEqual(viewModel.state, .failed(previous: nil))
    XCTAssertEqual(
      viewModel.failureMessage,
      "삭제되었거나 접근할 수 없어요."
    )
  }

  @MainActor
  func testDetail404RefreshDoesNotKeepDeletedDetail() async {
    let detail = routineGroupDetail(id: 12)
    let service = AccountRoutineGroupRemoteStub(
      detailResults: [
        .success(detail),
        .failure(
          .api(
            .server(
              statusCode: 404,
              code: nil,
              message: "not found"
            )
          )
        ),
      ]
    )
    let viewModel = AccountRoutineGroupDetailViewModel(
      remoteService: service
    )

    await viewModel.load(routineGroupID: 12, memberID: 98)
    await viewModel.load(routineGroupID: 12, memberID: 98)

    XCTAssertEqual(viewModel.state, .failed(previous: nil))
    XCTAssertEqual(
      viewModel.failureMessage,
      "삭제되었거나 접근할 수 없어요."
    )
  }

  @MainActor
  func testFailedDetailRefreshKeepsOnlySameGroupPreviousValue() async {
    let firstDetail = routineGroupDetail(id: 12)
    let service = AccountRoutineGroupRemoteStub(
      detailResults: [
        .success(firstDetail),
        .failure(.unavailable),
        .failure(.unavailable),
      ]
    )
    let viewModel = AccountRoutineGroupDetailViewModel(
      remoteService: service
    )

    await viewModel.load(routineGroupID: 12, memberID: 98)
    await viewModel.load(routineGroupID: 12, memberID: 98)

    XCTAssertEqual(viewModel.state, .failed(previous: firstDetail))

    await viewModel.load(routineGroupID: 13, memberID: 98)

    XCTAssertEqual(viewModel.state, .failed(previous: nil))
  }

  @MainActor
  func testDetailNeverPublishesStaleResponseAfterMemberChange() async {
    let service = DeferredAccountRoutineGroupRemoteStub()
    let viewModel = AccountRoutineGroupDetailViewModel(
      remoteService: service
    )

    let load = Task {
      await viewModel.load(routineGroupID: 12, memberID: 98)
    }
    await service.waitUntilDetailRequested()

    viewModel.accountDidChange(memberID: 99)
    await service.resumeDetail(returning: routineGroupDetail(id: 12))
    await load.value

    XCTAssertEqual(viewModel.state, .loading(previous: nil))
    XCTAssertNil(viewModel.failureMessage)
  }

  @MainActor
  func testDetailDisappearanceClearsMemoryAndCancelsRequest() async {
    let detail = routineGroupDetail(id: 12)
    let service = AccountRoutineGroupRemoteStub(
      detailResults: [.success(detail)]
    )
    let viewModel = AccountRoutineGroupDetailViewModel(
      remoteService: service
    )
    await viewModel.load(routineGroupID: 12, memberID: 98)

    viewModel.screenDidDisappear()

    XCTAssertEqual(viewModel.state, .loading(previous: nil))
    XCTAssertNil(viewModel.failureMessage)
  }

  @MainActor
  func testExpiredAuthenticationHasActionableMessage() async {
    let service = AccountRoutineGroupRemoteStub(
      listResults: [.failure(.api(.authenticationRequired))]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )

    await viewModel.load(memberID: 98)

    XCTAssertEqual(viewModel.state, .failed(previous: nil))
    XCTAssertEqual(
      viewModel.failureMessage,
      "로그인이 만료됐어요. 다시 로그인해 주세요."
    )
  }

  @MainActor
  func testAuthorizationContextChangeDropsPreviousAccountData() async {
    let previous = [routineGroupSummary(id: 98)]
    let service = AccountRoutineGroupRemoteStub(
      listResults: [
        .success(previous),
        .failure(.remote(.accountAuthorizationChanged)),
      ]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )

    await viewModel.load(memberID: 98)
    await viewModel.load(memberID: 98)

    XCTAssertEqual(viewModel.state, .failed(previous: nil))
    XCTAssertEqual(
      viewModel.failureMessage,
      "계정이 변경되어 서버 루틴을 표시하지 않았어요."
    )
  }

  func testDisplayTextPreservesMissingUnknownAndRawValues() {
    XCTAssertEqual(
      AccountRoutineGroupDisplayText.routineType(nil),
      "유형 확인 불가"
    )
    XCTAssertEqual(
      AccountRoutineGroupDisplayText.routineType(.unknown("FUTURE")),
      "확인되지 않은 유형 (FUTURE)"
    )
    XCTAssertEqual(
      AccountRoutineGroupDisplayText.weatherNotification(nil),
      "설정 확인 불가"
    )
    XCTAssertEqual(
      AccountRoutineGroupDisplayText.optionalDuration(nil),
      "시간 정보 없음"
    )
    XCTAssertEqual(
      AccountRoutineGroupDisplayText.duration(seconds: 3_661),
      "1시간 1분 1초"
    )
    XCTAssertEqual(
      AccountRoutineGroupDisplayText.step(
        ServerRoutineNestedStep(
          stepID: 1,
          content: nil,
          orderIndex: 0
        )
      ),
      "내용 확인 불가 · orderIndex 0"
    )
  }

  func testArchiveNavigationResetsEveryPresentationOnAccountChange() {
    var navigation = AccountRoutineGroupArchiveNavigationState()

    navigation.presentArchive()
    navigation.presentDetail(routineGroupID: 12)

    XCTAssertTrue(navigation.isArchivePresented)
    XCTAssertTrue(navigation.isDetailPresented)
    XCTAssertEqual(navigation.selectedRoutineGroupID, 12)

    navigation.reset()

    XCTAssertEqual(
      navigation,
      AccountRoutineGroupArchiveNavigationState()
    )
  }

  func testArchiveNavigationRejectsInvalidDetailIdentity() {
    var navigation = AccountRoutineGroupArchiveNavigationState()
    navigation.presentArchive()

    navigation.presentDetail(routineGroupID: 0)

    XCTAssertTrue(navigation.isArchivePresented)
    XCTAssertFalse(navigation.isDetailPresented)
    XCTAssertNil(navigation.selectedRoutineGroupID)
  }

  @MainActor
  func testArchiveEntryRequiresSignedInAccountAndRemoteService() {
    let signedIn = AccountSessionState.signedIn(
      SignedInAccount(
        memberID: 98,
        onboardingCompleted: true
      )
    )

    XCTAssertTrue(
      ProfileView.shouldShowAccountRoutineArchive(
        accountState: signedIn,
        hasRemoteService: true
      )
    )
    XCTAssertFalse(
      ProfileView.shouldShowAccountRoutineArchive(
        accountState: signedIn,
        hasRemoteService: false
      )
    )
    XCTAssertFalse(
      ProfileView.shouldShowAccountRoutineArchive(
        accountState: .signedOut,
        hasRemoteService: true
      )
    )
  }
}

private enum AccountRoutineGroupRemoteCall: Equatable, Sendable {
  case list(memberID: Int64)
  case detail(routineGroupID: Int64, memberID: Int64)
}

private enum AccountRoutineGroupTestError: Error, Sendable {
  case unavailable
  case cancelled
  case api(APIError)
  case remote(AccountRoutineGroupRemoteError)
}

private actor AccountRoutineGroupRemoteStub:
  AccountRoutineGroupRemoteServing {
  private var listResults:
    [Result<[ServerRoutineGroupSummary], AccountRoutineGroupTestError>]
  private var detailResults:
    [Result<ServerRoutineGroupDetail, AccountRoutineGroupTestError>]
  private(set) var calls: [AccountRoutineGroupRemoteCall] = []

  init(
    listResults:
      [Result<
        [ServerRoutineGroupSummary],
        AccountRoutineGroupTestError
      >] = [],
    detailResults:
      [Result<
        ServerRoutineGroupDetail,
        AccountRoutineGroupTestError
      >] = []
  ) {
    self.listResults = listResults
    self.detailResults = detailResults
  }

  func fetchRoutineGroups(
    memberID: Int64
  ) async throws -> [ServerRoutineGroupSummary] {
    calls.append(.list(memberID: memberID))
    return try resolved(listResults.removeFirst())
  }

  func fetchRoutineGroupDetail(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> ServerRoutineGroupDetail {
    calls.append(
      .detail(
        routineGroupID: routineGroupID,
        memberID: memberID
      )
    )
    return try resolved(detailResults.removeFirst())
  }

  private func resolved<Value>(
    _ result: Result<Value, AccountRoutineGroupTestError>
  ) throws -> Value {
    do {
      return try result.get()
    } catch AccountRoutineGroupTestError.cancelled {
      throw CancellationError()
    } catch AccountRoutineGroupTestError.api(let error) {
      throw error
    } catch AccountRoutineGroupTestError.remote(let error) {
      throw error
    }
  }
}

private actor DeferredAccountRoutineGroupRemoteStub:
  AccountRoutineGroupRemoteServing {
  private var listContinuation:
    CheckedContinuation<[ServerRoutineGroupSummary], Error>?
  private var detailContinuation:
    CheckedContinuation<ServerRoutineGroupDetail, Error>?

  func fetchRoutineGroups(
    memberID: Int64
  ) async throws -> [ServerRoutineGroupSummary] {
    try await withCheckedThrowingContinuation { continuation in
      listContinuation = continuation
    }
  }

  func fetchRoutineGroupDetail(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> ServerRoutineGroupDetail {
    try await withCheckedThrowingContinuation { continuation in
      detailContinuation = continuation
    }
  }

  func waitUntilListRequested() async {
    while listContinuation == nil {
      await Task.yield()
    }
  }

  func waitUntilDetailRequested() async {
    while detailContinuation == nil {
      await Task.yield()
    }
  }

  func resumeList(
    returning summaries: [ServerRoutineGroupSummary]
  ) {
    listContinuation?.resume(returning: summaries)
    listContinuation = nil
  }

  func resumeDetail(
    returning detail: ServerRoutineGroupDetail
  ) {
    detailContinuation?.resume(returning: detail)
    detailContinuation = nil
  }
}

private func routineGroupSummary(
  id: Int64,
  title: String? = "아침 루틴"
) -> ServerRoutineGroupSummary {
  ServerRoutineGroupSummary(
    routineGroupID: id,
    title: title,
    isActive: true,
    routineCount: 2,
    totalDurationSeconds: 180
  )
}

private func routineGroupDetail(
  id: Int64
) -> ServerRoutineGroupDetail {
  ServerRoutineGroupDetail(
    routineGroupID: id,
    title: "아침 루틴",
    description: "천천히 시작해요",
    alarmDaysRaw: "MON,TUE",
    alarmTimeRaw: "07:30",
    weatherNotificationEnabled: true,
    routines: [
      ServerRoutineItem(
        routineID: 31,
        title: "물 마시기",
        type: .check,
        durationSeconds: 30,
        steps: []
      ),
    ]
  )
}
