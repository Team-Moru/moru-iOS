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
  func testDetailDisappearanceClearsLoadedMemory() async {
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
  func testDetailDisappearanceDropsLateInFlightResponse() async {
    let service = DeferredAccountRoutineGroupRemoteStub()
    let viewModel = AccountRoutineGroupDetailViewModel(
      remoteService: service
    )

    let load = Task {
      await viewModel.load(routineGroupID: 12, memberID: 98)
    }
    await service.waitUntilDetailRequested()

    viewModel.screenDidDisappear()
    await service.resumeDetail(returning: routineGroupDetail(id: 12))
    await load.value

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

  @MainActor
  func testActivityAbsenceIsEmptyWhileNetworkFailureIsFailed() async {
    let service = AccountRoutineGroupRemoteStub(
      activeResults: [
        .success(nil),
        .failure(.unavailable),
      ],
      todayResults: [
        .success(nil),
        .failure(.unavailable),
      ]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )

    await viewModel.loadActivity(memberID: 98)

    XCTAssertEqual(viewModel.activeState, .empty)
    XCTAssertEqual(viewModel.todayState, .empty)
    XCTAssertNil(viewModel.activeFailureMessage)
    XCTAssertNil(viewModel.todayFailureMessage)

    await viewModel.loadActivity(memberID: 98)

    XCTAssertEqual(viewModel.activeState, .failed(previous: nil))
    XCTAssertEqual(viewModel.todayState, .failed(previous: nil))
    XCTAssertEqual(
      viewModel.activeFailureMessage,
      "사용 중인 서버 루틴을 불러오지 못했어요."
    )
    XCTAssertEqual(
      viewModel.todayFailureMessage,
      "오늘의 서버 루틴 현황을 불러오지 못했어요."
    )
  }

  @MainActor
  func testActivityROUTINE4005ResultClearsPreviousSnapshot() async {
    let active = activeRoutineGroup(id: 1)
    let progress = todayRoutineProgress(completedCount: 1, totalCount: 2)
    let service = AccountRoutineGroupRemoteStub(
      activeResults: [
        .success(active),
        .success(nil),
      ],
      todayResults: [
        .success(progress),
        .success(nil),
      ]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )

    await viewModel.loadActivity(memberID: 98)
    XCTAssertEqual(viewModel.activeState, .content(active))
    XCTAssertEqual(viewModel.todayState, .content(progress))

    await viewModel.loadActivity(memberID: 98)

    XCTAssertEqual(viewModel.activeState, .empty)
    XCTAssertEqual(viewModel.todayState, .empty)
    XCTAssertNil(viewModel.activeFailureMessage)
    XCTAssertNil(viewModel.todayFailureMessage)
  }

  @MainActor
  func testOrdinaryActivity404RemainsFailure() async {
    let ordinary404 = AccountRoutineGroupTestError.api(
      .server(
        statusCode: 404,
        code: "ROUTINE4040",
        message: "not found"
      )
    )
    let service = AccountRoutineGroupRemoteStub(
      activeResults: [.failure(ordinary404)],
      todayResults: [.failure(ordinary404)]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )

    await viewModel.loadActivity(memberID: 98)

    XCTAssertEqual(viewModel.activeState, .failed(previous: nil))
    XCTAssertEqual(viewModel.todayState, .failed(previous: nil))
  }

  @MainActor
  func testTodayPublishesWhileActiveRequestIsStillPending() async {
    let progress = todayRoutineProgress(completedCount: 1, totalCount: 2)
    let service = DeferredAccountRoutineGroupRemoteStub()
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )

    let load = Task {
      await viewModel.loadActivity(memberID: 98)
    }
    await service.waitUntilActiveRequested()
    await service.waitUntilTodayRequested()

    for _ in 0..<100 {
      guard viewModel.todayState != .content(progress) else {
        break
      }
      await Task.yield()
    }

    XCTAssertEqual(viewModel.activeState, .loading(previous: nil))
    XCTAssertEqual(viewModel.todayState, .content(progress))

    await service.resumeActive(returning: nil)
    await load.value

    XCTAssertEqual(viewModel.activeState, .empty)
  }

  @MainActor
  func testConcurrentAccountTransitionDropsEveryPreviousSnapshot()
    async {
    let previousSummaries = [routineGroupSummary(id: 1)]
    let previousActive = activeRoutineGroup(id: 1)
    let previousToday = todayRoutineProgress(
      completedCount: 1,
      totalCount: 2
    )
    let service = AccountRoutineGroupRemoteStub(
      listResults: [
        .success(previousSummaries),
        .failure(.unavailable),
      ],
      activeResults: [
        .success(previousActive),
        .failure(.unavailable),
      ],
      todayResults: [
        .success(previousToday),
        .failure(.unavailable),
      ]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )
    await viewModel.load(memberID: 98)
    await viewModel.loadActivity(memberID: 98)

    async let listLoad: Void = viewModel.load(memberID: 99)
    async let activityLoad: Void = viewModel.loadActivity(memberID: 99)
    _ = await (listLoad, activityLoad)

    XCTAssertEqual(viewModel.state, .failed(previous: nil))
    XCTAssertEqual(viewModel.activeState, .failed(previous: nil))
    XCTAssertEqual(viewModel.todayState, .failed(previous: nil))
  }

  @MainActor
  func testCancelledLoadsCannotRestoreAPreviousAccount() async {
    let service = AccountRoutineGroupRemoteStub(
      listResults: [.failure(.cancelled)],
      activeResults: [.failure(.cancelled)],
      todayResults: [.failure(.cancelled)]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )
    viewModel.accountDidChange(memberID: 99)

    let staleListLoad = Task {
      await Task.yield()
      await viewModel.load(memberID: 98)
    }
    let staleActivityLoad = Task {
      await Task.yield()
      await viewModel.loadActivity(memberID: 98)
    }
    staleListLoad.cancel()
    staleActivityLoad.cancel()
    await staleListLoad.value
    await staleActivityLoad.value

    XCTAssertEqual(viewModel.state, .loading(previous: nil))
    XCTAssertEqual(viewModel.activeState, .loading(previous: nil))
    XCTAssertEqual(viewModel.todayState, .loading(previous: nil))
    let calls = await service.calls
    XCTAssertEqual(calls, [])
  }

  @MainActor
  func testActivationRefreshesServerSnapshotsAndKeepsSingleActiveGroup()
    async {
    let initialSummaries = [
      routineGroupSummary(id: 1, isActive: true),
      routineGroupSummary(id: 2, isActive: false),
    ]
    let refreshedSummaries = [
      routineGroupSummary(id: 1, isActive: false),
      routineGroupSummary(id: 2, isActive: true),
    ]
    let initialActive = activeRoutineGroup(id: 1)
    let refreshedActive = activeRoutineGroup(id: 2)
    let initialToday = todayRoutineProgress(
      completedCount: 1,
      totalCount: 2
    )
    let refreshedToday = todayRoutineProgress(
      completedCount: 0,
      totalCount: 2
    )
    let service = AccountRoutineGroupRemoteStub(
      listResults: [
        .success(initialSummaries),
        .success(refreshedSummaries),
      ],
      activeResults: [
        .success(initialActive),
        .success(refreshedActive),
      ],
      todayResults: [
        .success(initialToday),
        .success(refreshedToday),
      ],
      activationResults: [
        .success(routineGroupActivation(id: 2, isActive: true)),
      ]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )

    await viewModel.load(memberID: 98)
    await viewModel.loadActivity(memberID: 98)
    await viewModel.updateActivation(
      routineGroupID: 2,
      isActive: true,
      memberID: 98
    )

    XCTAssertEqual(viewModel.state, .content(refreshedSummaries))
    XCTAssertEqual(viewModel.activeState, .content(refreshedActive))
    XCTAssertEqual(viewModel.todayState, .content(refreshedToday))
    XCTAssertNil(viewModel.activationFailureMessage)
    XCTAssertNil(viewModel.activatingRoutineGroupID)

    let calls = await service.calls
    XCTAssertEqual(
      calls.filter {
        if case .activation = $0 { return true }
        return false
      },
      [.activation(routineGroupID: 2, isActive: true, memberID: 98)]
    )
  }

  @MainActor
  func testRepeatedActivationUsesSameExplicitDesiredState() async {
    let inactive = [routineGroupSummary(id: 2, isActive: false)]
    let active = [routineGroupSummary(id: 2, isActive: true)]
    let activeGroup = activeRoutineGroup(id: 2)
    let today = todayRoutineProgress(completedCount: 0, totalCount: 1)
    let service = AccountRoutineGroupRemoteStub(
      listResults: [
        .success(inactive),
        .success(active),
        .success(active),
      ],
      activeResults: [
        .success(nil),
        .success(activeGroup),
        .success(activeGroup),
      ],
      todayResults: [
        .success(nil),
        .success(today),
        .success(today),
      ],
      activationResults: [
        .success(routineGroupActivation(id: 2, isActive: true)),
        .success(routineGroupActivation(id: 2, isActive: true)),
      ]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )
    await viewModel.load(memberID: 98)
    await viewModel.loadActivity(memberID: 98)

    await viewModel.updateActivation(
      routineGroupID: 2,
      isActive: true,
      memberID: 98
    )
    await viewModel.updateActivation(
      routineGroupID: 2,
      isActive: true,
      memberID: 98
    )

    let calls = await service.calls
    XCTAssertEqual(
      calls.filter {
        if case .activation = $0 { return true }
        return false
      },
      [
        .activation(routineGroupID: 2, isActive: true, memberID: 98),
        .activation(routineGroupID: 2, isActive: true, memberID: 98),
      ]
    )
    XCTAssertEqual(viewModel.state, .content(active))
  }

  @MainActor
  func testDeactivationMapsRefreshedROUTINE4005ToEmpty() async {
    let activeSummary = [routineGroupSummary(id: 2, isActive: true)]
    let inactiveSummary = [routineGroupSummary(id: 2, isActive: false)]
    let service = AccountRoutineGroupRemoteStub(
      listResults: [
        .success(activeSummary),
        .success(inactiveSummary),
      ],
      activeResults: [
        .success(activeRoutineGroup(id: 2)),
        .success(nil),
      ],
      todayResults: [
        .success(todayRoutineProgress(completedCount: 1, totalCount: 1)),
        .success(nil),
      ],
      activationResults: [
        .success(routineGroupActivation(id: 2, isActive: false)),
      ]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )
    await viewModel.load(memberID: 98)
    await viewModel.loadActivity(memberID: 98)

    await viewModel.updateActivation(
      routineGroupID: 2,
      isActive: false,
      memberID: 98
    )

    XCTAssertEqual(viewModel.state, .content(inactiveSummary))
    XCTAssertEqual(viewModel.activeState, .empty)
    XCTAssertEqual(viewModel.todayState, .empty)
  }

  @MainActor
  func testAmbiguousActivationFailureReloadsAuthoritativeSnapshots()
    async {
    let initialSummaries = [
      routineGroupSummary(id: 2, isActive: false),
    ]
    let refreshedSummaries = [
      routineGroupSummary(id: 2, isActive: true),
    ]
    let refreshedActive = activeRoutineGroup(id: 2)
    let refreshedToday = todayRoutineProgress(
      completedCount: 0,
      totalCount: 2
    )
    let service = AccountRoutineGroupRemoteStub(
      listResults: [
        .success(initialSummaries),
        .failure(.unavailable),
      ],
      activeResults: [
        .success(nil),
        .success(refreshedActive),
      ],
      todayResults: [
        .success(nil),
        .success(refreshedToday),
      ],
      activationResults: [.failure(.unavailable)]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )
    await viewModel.load(memberID: 98)
    await viewModel.loadActivity(memberID: 98)

    await viewModel.updateActivation(
      routineGroupID: 2,
      isActive: true,
      memberID: 98
    )

    XCTAssertEqual(
      viewModel.state,
      .failed(previous: refreshedSummaries)
    )
    XCTAssertEqual(viewModel.activeState, .content(refreshedActive))
    XCTAssertEqual(viewModel.todayState, .content(refreshedToday))
    XCTAssertNil(viewModel.activationFailureMessage)
  }

  @MainActor
  func testAmbiguousActivationFailureAndRefreshFailureShowsUnknownOutcome()
    async {
    let summaries = [routineGroupSummary(id: 2, isActive: false)]
    let service = AccountRoutineGroupRemoteStub(
      listResults: [
        .success(summaries),
        .failure(.unavailable),
      ],
      activeResults: [
        .success(nil),
        .failure(.unavailable),
      ],
      todayResults: [
        .success(nil),
        .failure(.unavailable),
      ],
      activationResults: [.failure(.unavailable)]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )
    await viewModel.load(memberID: 98)
    await viewModel.loadActivity(memberID: 98)

    await viewModel.updateActivation(
      routineGroupID: 2,
      isActive: true,
      memberID: 98
    )

    XCTAssertEqual(viewModel.state, .failed(previous: summaries))
    XCTAssertEqual(viewModel.activeState, .failed(previous: nil))
    XCTAssertEqual(viewModel.todayState, .failed(previous: nil))
    XCTAssertEqual(
      viewModel.activationFailureMessage,
      "사용 상태 변경 여부를 확인하지 못했어요. 다시 확인해 주세요."
    )
  }

  @MainActor
  func testActivityRetryResolvesPendingAmbiguousActivation() async {
    let summaries = [routineGroupSummary(id: 2, isActive: false)]
    let refreshedSummaries = [
      routineGroupSummary(id: 2, isActive: true),
    ]
    let refreshedActive = activeRoutineGroup(id: 2)
    let refreshedToday = todayRoutineProgress(
      completedCount: 1,
      totalCount: 2
    )
    let service = AccountRoutineGroupRemoteStub(
      listResults: [
        .success(summaries),
        .failure(.unavailable),
      ],
      activeResults: [
        .success(nil),
        .failure(.unavailable),
        .success(refreshedActive),
      ],
      todayResults: [
        .success(nil),
        .failure(.unavailable),
        .success(refreshedToday),
      ],
      activationResults: [.failure(.unavailable)]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )
    await viewModel.load(memberID: 98)
    await viewModel.loadActivity(memberID: 98)
    await viewModel.updateActivation(
      routineGroupID: 2,
      isActive: true,
      memberID: 98
    )
    XCTAssertEqual(
      viewModel.activationFailureMessage,
      "사용 상태 변경 여부를 확인하지 못했어요. 다시 확인해 주세요."
    )

    await viewModel.retryActivity(memberID: 98)

    XCTAssertEqual(
      viewModel.state,
      .failed(previous: refreshedSummaries)
    )
    XCTAssertEqual(viewModel.activeState, .content(refreshedActive))
    XCTAssertEqual(viewModel.todayState, .content(refreshedToday))
    XCTAssertNil(viewModel.activationFailureMessage)
  }

  @MainActor
  func testAmbiguousActivationFailureCanConfirmRequestedStateWasNotApplied()
    async {
    let summaries = [routineGroupSummary(id: 2, isActive: false)]
    let service = AccountRoutineGroupRemoteStub(
      listResults: [
        .success(summaries),
        .success(summaries),
      ],
      activeResults: [
        .success(nil),
        .success(nil),
      ],
      todayResults: [
        .success(nil),
        .success(nil),
      ],
      activationResults: [.failure(.unavailable)]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )
    await viewModel.load(memberID: 98)
    await viewModel.loadActivity(memberID: 98)

    await viewModel.updateActivation(
      routineGroupID: 2,
      isActive: true,
      memberID: 98
    )

    XCTAssertEqual(viewModel.state, .content(summaries))
    XCTAssertEqual(viewModel.activeState, .empty)
    XCTAssertEqual(
      viewModel.activationFailureMessage,
      "요청한 사용 상태가 서버에 반영되지 않았어요."
    )
  }

  @MainActor
  func testAmbiguousActivationErrorKindsAllTriggerVerification() async {
    let summaries = [routineGroupSummary(id: 2, isActive: false)]
    let ambiguousErrors: [AccountRoutineGroupTestError] = [
      .api(.transport(code: -1001, message: "timeout")),
      .api(.server(statusCode: 408, code: nil, message: "timeout")),
      .api(.server(statusCode: 429, code: nil, message: "retry")),
      .api(.server(statusCode: 500, code: nil, message: "failed")),
      .api(.decoding("invalid response")),
      .api(.missingResult(code: "COMMON200", message: "missing")),
      .remote(.invalidResponse),
    ]

    for error in ambiguousErrors {
      let service = AccountRoutineGroupRemoteStub(
        listResults: [
          .success(summaries),
          .success(summaries),
        ],
        activeResults: [
          .success(nil),
          .success(nil),
        ],
        todayResults: [
          .success(nil),
          .success(nil),
        ],
        activationResults: [.failure(error)]
      )
      let viewModel = AccountRoutineGroupListViewModel(
        remoteService: service
      )
      await viewModel.load(memberID: 98)
      await viewModel.loadActivity(memberID: 98)

      await viewModel.updateActivation(
        routineGroupID: 2,
        isActive: true,
        memberID: 98
      )

      let calls = await service.calls
      XCTAssertEqual(
        calls.filter { if case .list = $0 { true } else { false } }
          .count,
        2
      )
      XCTAssertEqual(
        viewModel.activationFailureMessage,
        "요청한 사용 상태가 서버에 반영되지 않았어요."
      )
    }
  }

  @MainActor
  func testNotFoundActivationRefreshesInsteadOfKeepingDeletedTarget()
    async {
    let summaries = [routineGroupSummary(id: 2, isActive: false)]
    let service = AccountRoutineGroupRemoteStub(
      listResults: [
        .success(summaries),
        .success([]),
      ],
      activeResults: [
        .success(nil),
        .success(nil),
      ],
      todayResults: [
        .success(nil),
        .success(nil),
      ],
      activationResults: [
        .failure(
          .api(
            .server(
              statusCode: 404,
              code: "ROUTINE4004",
              message: "not found"
            )
          )
        ),
      ]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )
    await viewModel.load(memberID: 98)
    await viewModel.loadActivity(memberID: 98)

    await viewModel.updateActivation(
      routineGroupID: 2,
      isActive: true,
      memberID: 98
    )

    XCTAssertEqual(viewModel.state, .empty)
    XCTAssertEqual(viewModel.activeState, .empty)
    XCTAssertEqual(
      viewModel.activationFailureMessage,
      "요청한 사용 상태가 서버에 반영되지 않았어요."
    )
  }

  @MainActor
  func testRejectedActivationKeepsSnapshotsWithoutRefresh() async {
    let summaries = [routineGroupSummary(id: 2, isActive: false)]
    let rejection = AccountRoutineGroupTestError.api(
      .server(
        statusCode: 409,
        code: "ROUTINE4006",
        message: "conflict"
      )
    )
    let service = AccountRoutineGroupRemoteStub(
      listResults: [.success(summaries)],
      activeResults: [.success(nil)],
      todayResults: [.success(nil)],
      activationResults: [.failure(rejection)]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )
    await viewModel.load(memberID: 98)
    await viewModel.loadActivity(memberID: 98)

    await viewModel.updateActivation(
      routineGroupID: 2,
      isActive: true,
      memberID: 98
    )

    XCTAssertEqual(viewModel.state, .content(summaries))
    XCTAssertEqual(viewModel.activeState, .empty)
    XCTAssertEqual(viewModel.todayState, .empty)
    XCTAssertEqual(
      viewModel.activationFailureMessage,
      "서버 루틴의 사용 상태를 변경하지 못했어요. 기존 상태를 유지해요."
    )
    let calls = await service.calls
    XCTAssertEqual(
      calls.filter { if case .list = $0 { true } else { false } }.count,
      1
    )
    XCTAssertEqual(
      calls.filter { if case .active = $0 { true } else { false } }.count,
      1
    )
    XCTAssertEqual(
      calls.filter { if case .today = $0 { true } else { false } }.count,
      1
    )
  }

  @MainActor
  func testActivationCancellationDoesNotRefreshOrShowFailure() async {
    let summaries = [routineGroupSummary(id: 2, isActive: false)]
    let service = AccountRoutineGroupRemoteStub(
      listResults: [.success(summaries)],
      activeResults: [.success(nil)],
      todayResults: [.success(nil)],
      activationResults: [.failure(.cancelled)]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )
    await viewModel.load(memberID: 98)
    await viewModel.loadActivity(memberID: 98)

    await viewModel.updateActivation(
      routineGroupID: 2,
      isActive: true,
      memberID: 98
    )

    XCTAssertEqual(viewModel.state, .content(summaries))
    XCTAssertEqual(viewModel.activeState, .empty)
    XCTAssertEqual(viewModel.todayState, .empty)
    XCTAssertNil(viewModel.activationFailureMessage)
    let calls = await service.calls
    XCTAssertEqual(
      calls.filter { if case .list = $0 { true } else { false } }.count,
      1
    )
  }

  @MainActor
  func testAccountChangeCancelsActivationAndAllowsNextAccountMutation()
    async {
    let service = DeferredAccountRoutineGroupRemoteStub()
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )
    viewModel.accountDidChange(memberID: 98)

    let previousAccountMutation = Task {
      await viewModel.updateActivation(
        routineGroupID: 1,
        isActive: true,
        memberID: 98
      )
    }
    await service.waitUntilActivationRequestCount(1)

    viewModel.accountDidChange(memberID: 99)
    XCTAssertNil(viewModel.activatingRoutineGroupID)

    await service.resumeNextActivation(
      throwing: AccountRoutineGroupRemoteError.invalidRequest
    )
    await previousAccountMutation.value

    let currentAccountMutation = Task {
      await viewModel.updateActivation(
        routineGroupID: 2,
        isActive: true,
        memberID: 99
      )
    }
    await service.waitUntilActivationRequestCount(2)

    await service.resumeNextActivation(
      throwing: AccountRoutineGroupRemoteError.invalidRequest
    )
    await currentAccountMutation.value

    XCTAssertNil(viewModel.activatingRoutineGroupID)
  }

  @MainActor
  func testAccountChangeCancelsAmbiguousFailureRecovery() async {
    let service = DeferredAccountRoutineGroupRemoteStub()
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )
    viewModel.accountDidChange(memberID: 98)

    let mutation = Task {
      await viewModel.updateActivation(
        routineGroupID: 1,
        isActive: true,
        memberID: 98
      )
    }
    await service.waitUntilActivationRequestCount(1)
    await service.resumeNextActivation(
      throwing: AccountRoutineGroupTestError.unavailable
    )
    await service.waitUntilListRequested()
    await service.waitUntilActiveRequested()

    viewModel.accountDidChange(memberID: 99)
    await service.resumeList(returning: [routineGroupSummary(id: 1)])
    await service.resumeActive(returning: nil)
    await mutation.value

    XCTAssertEqual(viewModel.state, .loading(previous: nil))
    XCTAssertEqual(viewModel.activeState, .loading(previous: nil))
    XCTAssertEqual(viewModel.todayState, .loading(previous: nil))
    XCTAssertNil(viewModel.activatingRoutineGroupID)
    XCTAssertNil(viewModel.activationFailureMessage)
  }

  @MainActor
  func testSuccessfulListRefreshClearsOldActivationFailure() async {
    let summaries = [routineGroupSummary(id: 2, isActive: false)]
    let service = AccountRoutineGroupRemoteStub(
      listResults: [
        .success(summaries),
        .success(summaries),
      ],
      activationResults: [
        .failure(
          .api(
            .server(
              statusCode: 409,
              code: "ROUTINE4006",
              message: "conflict"
            )
          )
        ),
      ]
    )
    let viewModel = AccountRoutineGroupListViewModel(
      remoteService: service
    )
    await viewModel.load(memberID: 98)
    await viewModel.updateActivation(
      routineGroupID: 2,
      isActive: true,
      memberID: 98
    )
    XCTAssertNotNil(viewModel.activationFailureMessage)

    await viewModel.load(memberID: 98)

    XCTAssertNil(viewModel.activationFailureMessage)
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
  case active(memberID: Int64)
  case today(memberID: Int64)
  case activation(routineGroupID: Int64, isActive: Bool, memberID: Int64)
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
  private var activeResults:
    [Result<ServerActiveRoutineGroup?, AccountRoutineGroupTestError>]
  private var todayResults:
    [Result<ServerTodayRoutineProgress?, AccountRoutineGroupTestError>]
  private var activationResults:
    [Result<ServerRoutineGroupActivation, AccountRoutineGroupTestError>]
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
      >] = [],
    activeResults:
      [Result<
        ServerActiveRoutineGroup?,
        AccountRoutineGroupTestError
      >] = [],
    todayResults:
      [Result<
        ServerTodayRoutineProgress?,
        AccountRoutineGroupTestError
      >] = [],
    activationResults:
      [Result<
        ServerRoutineGroupActivation,
        AccountRoutineGroupTestError
      >] = []
  ) {
    self.listResults = listResults
    self.detailResults = detailResults
    self.activeResults = activeResults
    self.todayResults = todayResults
    self.activationResults = activationResults
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

  func fetchActiveRoutineGroup(
    memberID: Int64
  ) async throws -> ServerActiveRoutineGroup? {
    calls.append(.active(memberID: memberID))
    return try resolved(activeResults.removeFirst())
  }

  func fetchTodayRoutineProgress(
    memberID: Int64
  ) async throws -> ServerTodayRoutineProgress? {
    calls.append(.today(memberID: memberID))
    return try resolved(todayResults.removeFirst())
  }

  func updateRoutineGroupActivation(
    routineGroupID: Int64,
    isActive: Bool,
    memberID: Int64
  ) async throws -> ServerRoutineGroupActivation {
    calls.append(
      .activation(
        routineGroupID: routineGroupID,
        isActive: isActive,
        memberID: memberID
      )
    )
    return try resolved(activationResults.removeFirst())
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
  private var activeContinuation:
    CheckedContinuation<ServerActiveRoutineGroup?, Error>?
  private var activeRequested = false
  private var todayRequested = false
  private var activationRequestCount = 0
  private var listRequestWaiters: [CheckedContinuation<Void, Never>] = []
  private var detailRequestWaiters: [CheckedContinuation<Void, Never>] = []
  private var activeRequestWaiters: [CheckedContinuation<Void, Never>] = []
  private var todayRequestWaiters: [CheckedContinuation<Void, Never>] = []
  private var activationRequestWaiters:
    [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
  private var activationContinuations:
    [CheckedContinuation<ServerRoutineGroupActivation, Error>] = []

  func fetchRoutineGroups(
    memberID: Int64
  ) async throws -> [ServerRoutineGroupSummary] {
    try await withCheckedThrowingContinuation { continuation in
      listContinuation = continuation
      let waiters = listRequestWaiters
      listRequestWaiters.removeAll()
      waiters.forEach { $0.resume() }
    }
  }

  func fetchRoutineGroupDetail(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> ServerRoutineGroupDetail {
    try await withCheckedThrowingContinuation { continuation in
      detailContinuation = continuation
      let waiters = detailRequestWaiters
      detailRequestWaiters.removeAll()
      waiters.forEach { $0.resume() }
    }
  }

  func fetchActiveRoutineGroup(
    memberID: Int64
  ) async throws -> ServerActiveRoutineGroup? {
    activeRequested = true
    return try await withCheckedThrowingContinuation { continuation in
      activeContinuation = continuation
      let waiters = activeRequestWaiters
      activeRequestWaiters.removeAll()
      waiters.forEach { $0.resume() }
    }
  }

  func fetchTodayRoutineProgress(
    memberID: Int64
  ) async throws -> ServerTodayRoutineProgress? {
    todayRequested = true
    let waiters = todayRequestWaiters
    todayRequestWaiters.removeAll()
    waiters.forEach { $0.resume() }
    return todayRoutineProgress(completedCount: 1, totalCount: 2)
  }

  func updateRoutineGroupActivation(
    routineGroupID: Int64,
    isActive: Bool,
    memberID: Int64
  ) async throws -> ServerRoutineGroupActivation {
    activationRequestCount += 1
    let readyWaiters = activationRequestWaiters.filter {
      activationRequestCount >= $0.count
    }
    activationRequestWaiters.removeAll {
      activationRequestCount >= $0.count
    }
    readyWaiters.forEach { $0.continuation.resume() }
    return try await withCheckedThrowingContinuation { continuation in
      activationContinuations.append(continuation)
    }
  }

  func waitUntilListRequested() async {
    guard listContinuation == nil else {
      return
    }
    await withCheckedContinuation { continuation in
      listRequestWaiters.append(continuation)
    }
  }

  func waitUntilDetailRequested() async {
    guard detailContinuation == nil else {
      return
    }
    await withCheckedContinuation { continuation in
      detailRequestWaiters.append(continuation)
    }
  }

  func waitUntilActiveRequested() async {
    guard !activeRequested || activeContinuation == nil else {
      return
    }
    await withCheckedContinuation { continuation in
      activeRequestWaiters.append(continuation)
    }
  }

  func waitUntilTodayRequested() async {
    guard !todayRequested else {
      return
    }
    await withCheckedContinuation { continuation in
      todayRequestWaiters.append(continuation)
    }
  }

  func waitUntilActivationRequestCount(_ expectedCount: Int) async {
    guard activationRequestCount < expectedCount else {
      return
    }
    await withCheckedContinuation { continuation in
      activationRequestWaiters.append((expectedCount, continuation))
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

  func resumeActive(returning active: ServerActiveRoutineGroup?) {
    activeContinuation?.resume(returning: active)
    activeContinuation = nil
  }

  func resumeNextActivation(throwing error: any Error) {
    guard !activationContinuations.isEmpty else {
      return
    }
    activationContinuations.removeFirst().resume(throwing: error)
  }
}

private func routineGroupSummary(
  id: Int64,
  title: String? = "아침 루틴",
  isActive: Bool? = true
) -> ServerRoutineGroupSummary {
  ServerRoutineGroupSummary(
    routineGroupID: id,
    title: title,
    isActive: isActive,
    routineCount: 2,
    totalDurationSeconds: 180
  )
}

private func activeRoutineGroup(
  id: Int64
) -> ServerActiveRoutineGroup {
  ServerActiveRoutineGroup(
    routineGroupID: id,
    title: "아침 루틴 \(id)",
    totalDurationSeconds: 180,
    completionRate: 0.5,
    routines: [
      ServerActiveRoutineItem(
        routineID: id * 10,
        title: "물 마시기",
        isCompleted: false,
        completedTimeSeconds: nil
      ),
    ]
  )
}

private func todayRoutineProgress(
  completedCount: Int,
  totalCount: Int
) -> ServerTodayRoutineProgress {
  ServerTodayRoutineProgress(
    completedCount: completedCount,
    totalCount: totalCount,
    completionRate: totalCount == 0
      ? 0
      : Double(completedCount) / Double(totalCount)
  )
}

private func routineGroupActivation(
  id: Int64,
  isActive: Bool
) -> ServerRoutineGroupActivation {
  ServerRoutineGroupActivation(
    routineGroupID: id,
    isActive: isActive
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
