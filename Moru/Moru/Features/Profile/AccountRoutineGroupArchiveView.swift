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
        readOnlyBanner
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
            await viewModel.load(memberID: memberID)
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
      await viewModel.load(memberID: memberID)
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
    .accessibilityIdentifier(
      "profile.account.routine-archive.read-only"
    )
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

      ForEach(summaries, id: \.routineGroupID) { summary in
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
      }
    }
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
    return false
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
