//
//  MainTabView.swift
//  Moru
//
//  Created by Codex on 7/13/26.
//

import SwiftUI

struct MainTabView: View {
  let dependencies: DependencyContainer
  let onSessionReloadNeeded: () -> Void

  @State private var selectedTab: MoruTabItem = .home

  var body: some View {
    ZStack(alignment: .bottom) {
      Group {
        switch selectedTab {
        case .home:
          HomeView(dependencies: dependencies)
        case .routine:
          RoutineSettingView(dependencies: dependencies)
        case .record:
          RecordPlaceholderView()
        case .my:
          MyPageView(
            dependencies: dependencies,
            onLocalDataReset: onSessionReloadNeeded
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      MoruTabBar(selection: $selectedTab)
    }
    .ignoresSafeArea(.keyboard, edges: .bottom)
  }
}

private struct RecordPlaceholderView: View {
  var body: some View {
    VStack(spacing: AppSpacing.sm) {
      Text("이력")
        .font(AppFont.heading2Bold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Text("루틴 기록 화면은 다음 작업에서 연결됩니다.")
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      LinearGradient(
        stops: [
          Gradient.Stop(color: AppColor.babyBlue100, location: 0),
          Gradient.Stop(color: AppColor.babyBlue50, location: 1),
        ],
        startPoint: UnitPoint(x: 0.5, y: 0),
        endPoint: UnitPoint(x: 0.5, y: 1)
      )
      .ignoresSafeArea()
    )
  }
}

#if DEBUG
#Preview {
  MainTabView(dependencies: .homePreview) {}
}
#endif
