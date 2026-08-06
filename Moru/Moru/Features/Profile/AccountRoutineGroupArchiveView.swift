//
//  AccountRoutineGroupArchiveView.swift
//  Moru
//

import SwiftUI

struct AccountRoutineGroupListView: View {
  static let rootAccessibilityIdentifier =
    "profile.account.routine-archive.list"

  @Bindable var viewModel: AccountRoutineGroupListViewModel
  let memberID: Int64?
  let onSelectRoutineGroup: (Int64) -> Void

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: MoruPilotSpacing.sixteen) {
        serverOnlyBanner
        activityOverview
        Text("모든 서버 루틴")
          .moruPilotTextStyle(.b3.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textStrong)
        content
      }
      .padding(MoruPilotSpacing.twenty)
    }
    .background(MoruPilotColor.canvas.ignoresSafeArea())
    .navigationTitle("서버 루틴 보관함")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task {
            await loadAll()
          }
        } label: {
          Label("새로고침", systemImage: "arrow.clockwise")
        }
        .disabled(isLoadingWithoutPrevious)
        .accessibilityIdentifier(
          "profile.account.routine-archive.refresh"
        )
      }
    }
    .task(id: memberID) {
      await loadAll()
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(Self.rootAccessibilityIdentifier)
  }

  private var serverOnlyBanner: some View {
    Label(
      "서버 전용 · 사용 상태만 바꾸며, 이 기기의 루틴과 합치거나 실행하지 않아요.",
      systemImage: "externaldrive.fill"
    )
    .moruPilotTextStyle(.c1)
    .foregroundStyle(MoruPilotColor.textSecondary)
    .fixedSize(horizontal: false, vertical: true)
    .padding(MoruPilotSpacing.sixteen)
    .frame(maxWidth: .infinity, alignment: .leading)
    .homePilotSurface(cornerRadius: MoruPilotSpacing.sixteen)
    .accessibilityIdentifier(
      "profile.account.routine-archive.server-only"
    )
  }

  private var activityOverview: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.twelve) {
      Text("현재 사용 중")
        .moruPilotTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)

      activeContent

      Divider()

      Text("오늘 진행 · KST")
        .moruPilotTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)

      todayContent

      if hasActivityFailure {
        activityRetryButton
      }
    }
    .padding(MoruPilotSpacing.sixteen)
    .frame(maxWidth: .infinity, alignment: .leading)
    .homePilotSurface(cornerRadius: MoruPilotSpacing.sixteen)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(
      "profile.account.routine-archive.activity"
    )
  }

  @ViewBuilder
  private var activeContent: some View {
    switch viewModel.activeState {
    case .signedOut:
      activityMessage("로그인하면 사용 중인 서버 루틴을 확인할 수 있어요.")
    case .unavailable:
      activityMessage("이 빌드에서는 사용 중인 서버 루틴을 확인할 수 없어요.")
    case .loading(previous: nil):
      activityLoading("사용 중인 서버 루틴을 불러오고 있어요.")
    case .loading(previous: let activeRoutineGroup?):
      activeRoutineGroupContent(
        activeRoutineGroup,
        notice: "서버에서 새로 확인하고 있어요."
      )
    case .content(let activeRoutineGroup):
      activeRoutineGroupContent(activeRoutineGroup)
    case .empty:
      activityMessage("사용 중인 서버 루틴이 없어요.")
    case .failed(previous: nil):
      activityMessage(
        viewModel.activeFailureMessage
          ?? "사용 중인 서버 루틴을 불러오지 못했어요."
      )
    case .failed(previous: let activeRoutineGroup?):
      activeRoutineGroupContent(
        activeRoutineGroup,
        notice: (viewModel.activeFailureMessage
          ?? "사용 중인 서버 루틴을 새로 불러오지 못했어요.")
          + " 이전 정보를 표시해요."
      )
    }
  }

  @ViewBuilder
  private var todayContent: some View {
    switch viewModel.todayState {
    case .signedOut:
      activityMessage("로그인하면 오늘 진행 현황을 확인할 수 있어요.")
    case .unavailable:
      activityMessage("이 빌드에서는 오늘 진행 현황을 확인할 수 없어요.")
    case .loading(previous: nil):
      activityLoading("오늘 진행 현황을 불러오고 있어요.")
    case .loading(previous: let progress?):
      todayProgressContent(
        progress,
        notice: "서버에서 새로 확인하고 있어요."
      )
    case .content(let progress):
      todayProgressContent(progress)
    case .empty:
      activityMessage("사용 중인 루틴이 없어 오늘 진행 현황도 비어 있어요.")
    case .failed(previous: nil):
      activityMessage(
        viewModel.todayFailureMessage
          ?? "오늘의 서버 루틴 현황을 불러오지 못했어요."
      )
    case .failed(previous: let progress?):
      todayProgressContent(
        progress,
        notice: (viewModel.todayFailureMessage
          ?? "오늘 진행 현황을 새로 불러오지 못했어요.")
          + " 이전 정보를 표시해요."
      )
    }
  }

  private func activeRoutineGroupContent(
    _ activeRoutineGroup: ServerActiveRoutineGroup,
    notice: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
      if let notice {
        activityNotice(notice)
      }
      Text(activeRoutineGroup.title ?? "제목 확인 불가")
        .moruPilotTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)
      Text(
        activeRoutineMetadata(activeRoutineGroup)
      )
      .moruPilotTextStyle(.c1)
      .foregroundStyle(MoruPilotColor.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func todayProgressContent(
    _ progress: ServerTodayRoutineProgress,
    notice: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
      if let notice {
        activityNotice(notice)
      }
      Text(
        "\(progress.completedCount)/\(progress.totalCount)개 완료 · "
          + AccountRoutineGroupDisplayText.percentage(
            progress.completionRate
          )
      )
      .moruPilotTextStyle(.b4.weight(.semiBold))
      .foregroundStyle(MoruPilotColor.textStrong)
      .accessibilityIdentifier(
        "profile.account.routine-archive.today-progress"
      )
    }
  }

  private func activeRoutineMetadata(
    _ activeRoutineGroup: ServerActiveRoutineGroup
  ) -> String {
    let duration = activeRoutineGroup.totalDurationSeconds.map {
      "총 \(AccountRoutineGroupDisplayText.duration(seconds: $0))"
    } ?? "총 시간 정보 없음"
    let completionRate = activeRoutineGroup.completionRate.map {
      AccountRoutineGroupDisplayText.percentage($0)
    } ?? "완료율 정보 없음"
    let routineCount = activeRoutineGroup.routines.map {
      "루틴 \($0.count)개"
    } ?? "루틴 수 정보 없음"
    return "\(routineCount) · \(duration) · \(completionRate)"
  }

  private func activityLoading(_ message: String) -> some View {
    HStack(spacing: MoruPilotSpacing.eight) {
      ProgressView()
      activityMessage(message)
    }
  }

  private func activityMessage(_ message: String) -> some View {
    Text(message)
      .moruPilotTextStyle(.c1)
      .foregroundStyle(MoruPilotColor.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func activityNotice(_ message: String) -> some View {
    Text(message)
      .moruPilotTextStyle(.c2)
      .foregroundStyle(MoruPilotColor.textTertiary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var activityRetryButton: some View {
    Button("현재 상태 다시 확인") {
      Task {
        await viewModel.retryActivity(memberID: memberID)
      }
    }
    .buttonStyle(.bordered)
    .tint(MoruPilotColor.accent)
    .accessibilityIdentifier(
      "profile.account.routine-archive.activity-retry"
    )
  }

  private var hasActivityFailure: Bool {
    if case .failed = viewModel.activeState {
      return true
    }
    if case .failed = viewModel.todayState {
      return true
    }
    return false
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.state {
    case .signedOut:
      messageView("로그인하면 서버 루틴을 확인할 수 있어요.")
    case .unavailable:
      messageView("이 빌드에서는 서버 루틴을 확인할 수 없어요.")
    case .loading(previous: nil):
      loadingView
    case .loading(previous: let summaries?):
      list(
        summaries,
        notice: "서버에서 새로 불러오는 동안 이전 정보를 표시해요."
      )
    case .content(let summaries):
      list(summaries)
    case .empty:
      messageView("계정에 저장된 서버 루틴이 없어요.")
    case .failed(previous: nil):
      failureView
    case .failed(previous: let summaries?):
      list(
        summaries,
        notice: (viewModel.failureMessage
          ?? "서버 루틴을 새로 불러오지 못했어요.")
          + " 이전 정보를 표시해요."
      )
      retryButton
    }
  }

  private var loadingView: some View {
    HStack(spacing: MoruPilotSpacing.twelve) {
      ProgressView()
      Text("서버 루틴을 불러오고 있어요.")
        .moruPilotTextStyle(.b4)
        .foregroundStyle(MoruPilotColor.textSecondary)
    }
    .frame(maxWidth: .infinity, minHeight: 120)
    .accessibilityElement(children: .combine)
  }

  private func list(
    _ summaries: [ServerRoutineGroupSummary],
    notice: String? = nil
  ) -> some View {
    LazyVStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      if let notice {
        Text(notice)
          .moruPilotTextStyle(.c1)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let activationFailureMessage =
        viewModel.activationFailureMessage {
        Text(activationFailureMessage)
          .moruPilotTextStyle(.c1)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier(
            "profile.account.routine-archive.activation-error"
          )
      }

      ForEach(summaries, id: \.routineGroupID) { summary in
        VStack(alignment: .trailing, spacing: MoruPilotSpacing.eight) {
          Button {
            onSelectRoutineGroup(summary.routineGroupID)
          } label: {
            AccountRoutineGroupSummaryRow(summary: summary)
          }
          .buttonStyle(.plain)
          .accessibilityHint("서버 루틴 상세를 엽니다.")
          .accessibilityIdentifier(
            "profile.account.routine-archive.group."
              + "\(summary.routineGroupID)"
          )

          activationButton(for: summary)
        }
      }
    }
  }

  @ViewBuilder
  private func activationButton(
    for summary: ServerRoutineGroupSummary
  ) -> some View {
    Button {
      Task {
        await viewModel.updateActivation(
          routineGroupID: summary.routineGroupID,
          isActive: summary.isActive != true,
          memberID: memberID
        )
      }
    } label: {
      if viewModel.activatingRoutineGroupID == summary.routineGroupID {
        ProgressView()
          .controlSize(.small)
      } else {
        Text(summary.isActive == true ? "사용 중지" : "사용하기")
      }
    }
    .buttonStyle(.bordered)
    .tint(summary.isActive == true
      ? MoruPilotColor.textSecondary
      : MoruPilotColor.accent)
    .disabled(viewModel.activatingRoutineGroupID != nil)
    .accessibilityIdentifier(
      "profile.account.routine-archive.activation."
        + "\(summary.routineGroupID)"
    )
  }

  private var failureView: some View {
    VStack(spacing: MoruPilotSpacing.twelve) {
      messageView(
        viewModel.failureMessage ?? "서버 루틴을 불러오지 못했어요."
      )
      retryButton
    }
    .frame(maxWidth: .infinity)
  }

  private var retryButton: some View {
    Button("다시 시도") {
      Task {
        await viewModel.retry(memberID: memberID)
      }
    }
    .buttonStyle(.bordered)
    .tint(MoruPilotColor.accent)
    .accessibilityIdentifier(
      "profile.account.routine-archive.retry"
    )
  }

  private func messageView(_ message: String) -> some View {
    Text(message)
      .moruPilotTextStyle(.b4)
      .foregroundStyle(MoruPilotColor.textSecondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, minHeight: 120)
  }

  private var isLoadingWithoutPrevious: Bool {
    if case .loading(previous: nil) = viewModel.state {
      return true
    }
    if case .loading(previous: nil) = viewModel.activeState {
      return true
    }
    if case .loading(previous: nil) = viewModel.todayState {
      return true
    }
    return viewModel.activatingRoutineGroupID != nil
  }

  private func loadAll() async {
    async let listLoad: Void = viewModel.load(memberID: memberID)
    async let activityLoad: Void = viewModel.loadActivity(memberID: memberID)
    _ = await (listLoad, activityLoad)
  }
}

private struct AccountRoutineGroupSummaryRow: View {
  let summary: ServerRoutineGroupSummary

  var body: some View {
    HStack(spacing: MoruPilotSpacing.twelve) {
      Image(systemName: "archivebox.fill")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MoruPilotColor.accent)
        .frame(width: 30)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
        Text(summary.title ?? "제목 확인 불가")
          .moruPilotTextStyle(.b4.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textStrong)
          .fixedSize(horizontal: false, vertical: true)

        Text(statusText)
          .moruPilotTextStyle(.c1)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)

        Text(metadataText)
          .moruPilotTextStyle(.c2)
          .foregroundStyle(MoruPilotColor.textTertiary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: MoruPilotSpacing.eight)
      MoruChevron(color: MoruPilotColor.textPrimary)
    }
    .padding(MoruPilotSpacing.sixteen)
    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
    .homePilotSurface(cornerRadius: MoruPilotSpacing.sixteen)
    .accessibilityElement(children: .combine)
  }

  private var statusText: String {
    switch summary.isActive {
    case true:
      "활성"
    case false:
      "비활성"
    case nil:
      "활성 상태 확인 불가"
    }
  }

  private var metadataText: String {
    let routineCount = summary.routineCount.map {
      "루틴 \($0)개"
    } ?? "루틴 수 정보 없음"
    let duration = summary.totalDurationSeconds.map {
      "총 \(AccountRoutineGroupDisplayText.duration(seconds: $0))"
    } ?? "총 시간 정보 없음"
    return "\(routineCount) · \(duration)"
  }
}

struct AccountRoutineGroupDetailView: View {
  static let rootAccessibilityIdentifier =
    "profile.account.routine-archive.detail"

  @Bindable var viewModel: AccountRoutineGroupDetailViewModel
  let routineGroupID: Int64
  let memberID: Int64?

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: MoruPilotSpacing.sixteen) {
        readOnlyBanner
        content
      }
      .padding(MoruPilotSpacing.twenty)
    }
    .background(MoruPilotColor.canvas.ignoresSafeArea())
    .navigationTitle("서버 루틴 상세")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task {
            await viewModel.load(
              routineGroupID: routineGroupID,
              memberID: memberID
            )
          }
        } label: {
          Label("새로고침", systemImage: "arrow.clockwise")
        }
        .disabled(isLoadingWithoutPrevious)
      }
    }
    .task(id: AccountRoutineGroupDetailTaskID(
      memberID: memberID,
      routineGroupID: routineGroupID
    )) {
      await viewModel.load(
        routineGroupID: routineGroupID,
        memberID: memberID
      )
    }
    .onDisappear {
      viewModel.screenDidDisappear()
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(Self.rootAccessibilityIdentifier)
  }

  private var readOnlyBanner: some View {
    Label(
      "읽기 전용 · 이 기기의 루틴과 합치거나 실행하지 않아요.",
      systemImage: "lock.fill"
    )
    .moruPilotTextStyle(.c1)
    .foregroundStyle(MoruPilotColor.textSecondary)
    .fixedSize(horizontal: false, vertical: true)
    .padding(MoruPilotSpacing.sixteen)
    .frame(maxWidth: .infinity, alignment: .leading)
    .homePilotSurface(cornerRadius: MoruPilotSpacing.sixteen)
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.state {
    case .signedOut:
      messageView("로그인하면 서버 루틴 상세를 확인할 수 있어요.")
    case .unavailable:
      messageView("이 빌드에서는 서버 루틴 상세를 확인할 수 없어요.")
    case .loading(previous: nil):
      loadingView
    case .loading(previous: let detail?):
      detailContent(
        detail,
        notice: "서버에서 새로 불러오는 동안 이전 정보를 표시해요."
      )
    case .content(let detail):
      detailContent(detail)
    case .empty:
      messageView("서버 루틴 상세 정보가 없어요.")
    case .failed(previous: nil):
      failureView
    case .failed(previous: let detail?):
      detailContent(
        detail,
        notice: (viewModel.failureMessage
          ?? "서버 루틴 상세를 새로 불러오지 못했어요.")
          + " 이전 정보를 표시해요."
      )
      retryButton
    }
  }

  private var loadingView: some View {
    HStack(spacing: MoruPilotSpacing.twelve) {
      ProgressView()
      Text("서버 루틴 상세를 불러오고 있어요.")
        .moruPilotTextStyle(.b4)
        .foregroundStyle(MoruPilotColor.textSecondary)
    }
    .frame(maxWidth: .infinity, minHeight: 120)
    .accessibilityElement(children: .combine)
  }

  private func detailContent(
    _ detail: ServerRoutineGroupDetail,
    notice: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.sixteen) {
      if let notice {
        Text(notice)
          .moruPilotTextStyle(.c1)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
        Text(detail.title ?? "제목 확인 불가")
          .moruPilotTextStyle(.b2.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textStrong)
          .fixedSize(horizontal: false, vertical: true)
        Text(detail.description ?? "설명 확인 불가")
          .moruPilotTextStyle(.b4)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .accountRoutineGroupSurface()

      VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
        AccountRoutineGroupMetadataRow(
          title: "알람 요일 원문",
          value: detail.alarmDaysRaw ?? "설정 없음"
        )
        AccountRoutineGroupMetadataRow(
          title: "알람 시간 원문",
          value: detail.alarmTimeRaw ?? "설정 없음"
        )
        AccountRoutineGroupMetadataRow(
          title: "날씨 알림",
          value: AccountRoutineGroupDisplayText.weatherNotification(
            detail.weatherNotificationEnabled
          )
        )
      }
      .accountRoutineGroupSurface()

      routineSection(detail.routines)
    }
  }

  @ViewBuilder
  private func routineSection(
    _ routines: [ServerRoutineItem]?
  ) -> some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      Text("루틴")
        .moruPilotTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)

      switch routines {
      case nil:
        messageView("루틴 정보 확인 불가")
      case .some([]):
        messageView("등록된 루틴 없음")
      case .some(let routines):
        ForEach(routines, id: \.routineID) { routine in
          AccountRoutineItemView(routine: routine)
        }
      }
    }
  }

  private var failureView: some View {
    VStack(spacing: MoruPilotSpacing.twelve) {
      messageView(
        viewModel.failureMessage ?? "서버 루틴 상세를 불러오지 못했어요."
      )
      retryButton
    }
    .frame(maxWidth: .infinity)
  }

  private var retryButton: some View {
    Button("다시 시도") {
      Task {
        await viewModel.retry(
          routineGroupID: routineGroupID,
          memberID: memberID
        )
      }
    }
    .buttonStyle(.bordered)
    .tint(MoruPilotColor.accent)
  }

  private func messageView(_ message: String) -> some View {
    Text(message)
      .moruPilotTextStyle(.b4)
      .foregroundStyle(MoruPilotColor.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, minHeight: 80)
  }

  private var isLoadingWithoutPrevious: Bool {
    if case .loading(previous: nil) = viewModel.state {
      return true
    }
    return false
  }
}

private struct AccountRoutineGroupDetailTaskID: Hashable {
  let memberID: Int64?
  let routineGroupID: Int64
}

private struct AccountRoutineGroupMetadataRow: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
      Text(title)
        .moruPilotTextStyle(.c2.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textTertiary)
      Text(value)
        .moruPilotTextStyle(.b4)
        .foregroundStyle(MoruPilotColor.textStrong)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }
}

private struct AccountRoutineItemView: View {
  let routine: ServerRoutineItem

  var body: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      Text(routine.title ?? "제목 확인 불가")
        .moruPilotTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)
        .fixedSize(horizontal: false, vertical: true)

      Text(
        "\(AccountRoutineGroupDisplayText.routineType(routine.type))"
          + " · "
          + AccountRoutineGroupDisplayText.optionalDuration(
            routine.durationSeconds
          )
      )
      .moruPilotTextStyle(.c1)
      .foregroundStyle(MoruPilotColor.textSecondary)
      .fixedSize(horizontal: false, vertical: true)

      stepSection
    }
    .accountRoutineGroupSurface()
  }

  @ViewBuilder
  private var stepSection: some View {
    switch routine.steps {
    case nil:
      Text("단계 정보 확인 불가")
        .accountRoutineGroupStepText()
    case .some([]):
      Text("등록된 단계 없음")
        .accountRoutineGroupStepText()
    case .some(let steps):
      VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
        ForEach(steps, id: \.stepID) { step in
          HStack(alignment: .firstTextBaseline, spacing: MoruPilotSpacing.eight) {
            Image(systemName: "circle.fill")
              .font(.system(size: 5))
              .foregroundStyle(MoruPilotColor.textTertiary)
              .accessibilityHidden(true)
            Text(AccountRoutineGroupDisplayText.step(step))
              .accountRoutineGroupStepText()
          }
        }
      }
    }
  }
}

nonisolated enum AccountRoutineGroupDisplayText {
  static func percentage(_ normalizedValue: Double) -> String {
    "\(Int((normalizedValue * 100).rounded()))%"
  }

  static func duration(seconds: Int) -> String {
    let hours = seconds / 3_600
    let minutes = seconds % 3_600 / 60
    let remainingSeconds = seconds % 60
    var parts: [String] = []
    if hours > 0 {
      parts.append("\(hours)시간")
    }
    if minutes > 0 {
      parts.append("\(minutes)분")
    }
    if remainingSeconds > 0 || parts.isEmpty {
      parts.append("\(remainingSeconds)초")
    }
    return parts.joined(separator: " ")
  }

  static func optionalDuration(_ seconds: Int?) -> String {
    seconds.map { duration(seconds: $0) } ?? "시간 정보 없음"
  }

  static func weatherNotification(_ isEnabled: Bool?) -> String {
    switch isEnabled {
    case true:
      "사용"
    case false:
      "사용 안 함"
    case nil:
      "설정 확인 불가"
    }
  }

  static func routineType(_ type: ServerRoutineItemType?) -> String {
    switch type {
    case .check:
      "체크"
    case .timer:
      "타이머"
    case .input:
      "입력"
    case .unknown(let rawValue):
      "확인되지 않은 유형 (\(rawValue))"
    case nil:
      "유형 확인 불가"
    }
  }

  static func step(_ step: ServerRoutineNestedStep) -> String {
    let content = step.content ?? "내용 확인 불가"
    guard let orderIndex = step.orderIndex else {
      return content
    }
    return "\(content) · orderIndex \(orderIndex)"
  }
}

private extension View {
  func accountRoutineGroupSurface() -> some View {
    padding(MoruPilotSpacing.sixteen)
      .frame(maxWidth: .infinity, alignment: .leading)
      .homePilotSurface(cornerRadius: MoruPilotSpacing.sixteen)
  }

  func accountRoutineGroupStepText() -> some View {
    moruPilotTextStyle(.c1)
      .foregroundStyle(MoruPilotColor.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}
