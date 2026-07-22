//
//  MainTabView.swift
//  Moru
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

struct MainTabState: Equatable {
  static let availableTabs: [MoruTabItem] = [.home, .routine, .record, .my]

  private(set) var selection: MoruTabItem = .home
  private(set) var historyReloadToken = 0

  mutating func select(_ tab: MoruTabItem) {
    guard Self.availableTabs.contains(tab) else {
      return
    }

    selection = tab

    guard tab == .record else {
      return
    }

    historyReloadToken += 1
  }
}

struct MainTabView: View {
  @State private var state = MainTabState()

  private let home: AnyView
  private let routineSetting: RoutineSettingView
  private let history: AnyView
  private let profile: AnyView

  init(
    home: AnyView,
    routineSetting: RoutineSettingView,
    history: AnyView,
    profile: AnyView = AnyView(EmptyView())
  ) {
    self.home = home
    self.routineSetting = routineSetting
    self.history = history
    self.profile = profile
  }

  var body: some View {
    VStack(spacing: 0) {
      selectedContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      MoruTabBar(
        selection: Binding(
          get: { state.selection },
          set: { state.select($0) }
        ),
        items: MainTabState.availableTabs
      )
    }
  }

  @ViewBuilder
  private var selectedContent: some View {
    if state.selection == .home {
      home
    } else if state.selection == .routine {
      routineSetting
    } else if state.selection == .record {
      history.id(state.historyReloadToken)
    } else {
      profile
    }
  }
}
