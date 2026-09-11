//
//  MainTabView.swift
//  Moru
//
//  Created by Codex on 7/14/26.
//

import Foundation
import SwiftUI

/// 하단 탭 4개. 아이콘은 SF Symbol이 아니라 브랜드 에셋이다.
enum MoruTabItem: String, CaseIterable, Identifiable {
  case home
  case routine
  case record
  case my

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home:
      "홈"
    case .routine:
      "루틴"
    case .record:
      "이력"
    case .my:
      "마이"
    }
  }

  var iconName: String {
    switch self {
    case .home:
      AppIcon.moruTabHome
    case .routine:
      AppIcon.moruTabRoutine
    case .record:
      AppIcon.moruTabRecord
    case .my:
      AppIcon.moruTabMy
    }
  }

  /// 탭 자체의 식별자(계약 테스트용). 네이티브 `Tab`에 `.accessibilityIdentifier`를
  /// 걸어도 실제 탭바 버튼에는 반영되지 않는다(2026-09-11, iOS 26.5 시뮬레이터에서
  /// UI 테스트로 확인 — 탭바 버튼은 `identifier` 없이 `label: title`만 노출한다).
  /// 그래서 UI 테스트는 이 문자열이 아니라 `title`(레이블)로 탭을 찾는다.
  var accessibilityIdentifier: String {
    "app.tab.\(rawValue)"
  }

  /// 탭바 컨테이너의 접근성 식별자. TabView 전체에는 정상적으로 반영된다.
  static let containerAccessibilityIdentifier = "app.tabBar"
}

struct MainTabState: Equatable {
  static let availableTabs: [MoruTabItem] = [.home, .routine, .record, .my]

  private(set) var selection: MoruTabItem
  private(set) var historyReloadToken: Int
  private(set) var historyDestination: HistoryDestination?

  init(
    selection: MoruTabItem = .home,
    historyReloadToken: Int = 0,
    historyDestination: HistoryDestination? = nil
  ) {
    self.selection = selection
    self.historyReloadToken = historyReloadToken
    self.historyDestination = historyDestination
  }

  mutating func select(_ tab: MoruTabItem) {
    guard Self.availableTabs.contains(tab) else {
      return
    }

    selection = tab
    historyDestination = nil

    guard tab == .record else {
      return
    }

    historyReloadToken += 1
  }

  mutating func showHome() {
    selection = .home
    historyDestination = nil
  }

  mutating func showRunDetail(_ runID: UUID) {
    selection = .record
    historyDestination = .runDetail(runID)
    historyReloadToken += 1
  }

  mutating func setHistoryDestination(_ destination: HistoryDestination?) {
    historyDestination = destination
  }
}

/// 탭 루트 4개를 네이티브 TabView에 담는다. 각 탭의 정체성·새로고침은 빌더가 정한다
/// (Home: sessionID + refreshToken, History: 회원 + reloadToken, Profile: 회원).
/// 네이티브 TabView는 탭을 오갈 때 화면 상태를 보존한다(스크롤 위치 등) — 기록 탭만
/// reloadToken으로 데이터를 다시 불러와 "매일 아침 초기 상태"를 유지한다.
struct MainTabView<Home: View, Routine: View, History: View, Profile: View>: View {
  private let home: Home
  private let routineSetting: Routine
  private let history: History
  private let profile: Profile
  @Binding private var selection: MoruTabItem

  init(
    home: Home,
    routineSetting: Routine,
    history: History,
    profile: Profile,
    selection: Binding<MoruTabItem>
  ) {
    self.home = home
    self.routineSetting = routineSetting
    self.history = history
    self.profile = profile
    _selection = selection
  }

  var body: some View {
    // 탭 버튼 자체는 .accessibilityIdentifier가 반영되지 않아 title(레이블)로만 구분된다.
    TabView(selection: $selection) {
      Tab(MoruTabItem.home.title, image: MoruTabItem.home.iconName, value: MoruTabItem.home) {
        home
      }

      Tab(
        MoruTabItem.routine.title,
        image: MoruTabItem.routine.iconName,
        value: MoruTabItem.routine
      ) {
        routineSetting
      }

      Tab(
        MoruTabItem.record.title,
        image: MoruTabItem.record.iconName,
        value: MoruTabItem.record
      ) {
        history
      }

      Tab(MoruTabItem.my.title, image: MoruTabItem.my.iconName, value: MoruTabItem.my) {
        profile
      }
    }
    .tint(MoruColor.accent)
    .accessibilityIdentifier(MoruTabItem.containerAccessibilityIdentifier)
  }
}

extension MainTabView where Profile == EmptyView {
  init(
    home: Home,
    routineSetting: Routine,
    history: History,
    selection: Binding<MoruTabItem>
  ) {
    self.init(
      home: home,
      routineSetting: routineSetting,
      history: history,
      profile: EmptyView(),
      selection: selection
    )
  }
}
