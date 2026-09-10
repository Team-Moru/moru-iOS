//
//  MainTabView.swift
//  Moru
//
//  Created by Codex on 7/14/26.
//

import Foundation
import SwiftUI

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

/// 탭 루트 4개를 담는다. 각 탭의 정체성·새로고침은 빌더가 정한다(Home: sessionID + refreshToken,
/// History: 회원 + reloadToken, Profile: 회원).
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
    selectedContent
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        MoruTabBar(
          selection: $selection,
          items: MainTabState.availableTabs
        )
      }
  }

  @ViewBuilder
  private var selectedContent: some View {
    if selection == .home {
      home
    } else if selection == .routine {
      routineSetting
    } else if selection == .record {
      history
    } else {
      profile
    }
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
