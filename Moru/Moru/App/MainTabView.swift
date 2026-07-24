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

struct MainTabView: View {
  private let home: AnyView
  private let routineSetting: RoutineSettingView
  private let history: AnyView
  private let profile: AnyView
  @Binding private var selection: MoruTabItem
  private let historyReloadToken: Int

  init(
    home: AnyView,
    routineSetting: RoutineSettingView,
    history: AnyView,
    profile: AnyView = AnyView(EmptyView()),
    selection: Binding<MoruTabItem>,
    historyReloadToken: Int
  ) {
    self.home = home
    self.routineSetting = routineSetting
    self.history = history
    self.profile = profile
    _selection = selection
    self.historyReloadToken = historyReloadToken
  }

  var body: some View {
    selectedContent
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        MoruTabBar(
          selection: $selection,
          items: MainTabState.availableTabs,
          componentStyle: .figmaPilot
        )
        .background {
          AppColor.grayWhite
            .opacity(0.7)
            .background(.ultraThinMaterial)
            .ignoresSafeArea(edges: .bottom)
        }
      }
  }

  @ViewBuilder
  private var selectedContent: some View {
    if selection == .home {
      home
    } else if selection == .routine {
      routineSetting
    } else if selection == .record {
      history.id(historyReloadToken)
    } else {
      profile
    }
  }
}
