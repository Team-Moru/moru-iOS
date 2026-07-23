//
//  MoruTabBar.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

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
}

struct MoruTabBar: View {
  static let accessibilityIdentifier = "app.tabBar"

  static func accessibilityIdentifier(for item: MoruTabItem) -> String {
    "app.tab.\(item.rawValue)"
  }

  @Binding var selection: MoruTabItem
  let items: [MoruTabItem]
  let componentStyle: MoruPilotComponentStyle
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    selection: Binding<MoruTabItem>,
    items: [MoruTabItem] = MoruTabItem.allCases,
    componentStyle: MoruPilotComponentStyle = .legacy
  ) {
    _selection = selection
    self.items = items
    self.componentStyle = componentStyle
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(items) { item in
        Button {
          selection = item
        } label: {
          VStack(spacing: AppSpacing.xxs) {
            Image(item.iconName)
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .foregroundStyle(
                selection == item ? selectedColor : unselectedColor
              )
              .frame(
                width: dynamicTypeSize.isAccessibilitySize ? 40 : 60,
                height: dynamicTypeSize.isAccessibilitySize ? 32 : 24
              )
              .accessibilityHidden(true)

            if !dynamicTypeSize.isAccessibilitySize {
              Text(item.title)
                .font(
                  selection == item
                    ? AppFont.pretendardMedium(size: 10)
                    : AppFont.pretendardRegular(size: 10)
                )
                .foregroundStyle(
                  selection == item ? selectedColor : unselectedColor
                )
            }
          }
          .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 52 : 45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selection == item ? .isSelected : [])
        .accessibilityIdentifier(Self.accessibilityIdentifier(for: item))
      }
    }
    .frame(maxWidth: .infinity, minHeight: 45)
    .padding(.horizontal, AppSpacing.screenHorizontal)
    .frame(
      maxWidth: .infinity,
      minHeight: minimumHeight
    )
    .background {
      if componentStyle == .figmaPilot {
        AppColor.grayWhite
          .opacity(0.7)
          .background(.ultraThinMaterial)
      } else {
        AppColor.grayWhite
      }
    }
    .shadow(
      color: componentStyle == .figmaPilot
        ? Color(red: 2 / 255, green: 24 / 255, blue: 100 / 255).opacity(0.05)
        : .clear,
      radius: componentStyle == .figmaPilot ? 10 : 0,
      x: 0,
      y: componentStyle == .figmaPilot ? -2 : 0
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(Self.accessibilityIdentifier)
  }

  private var selectedColor: Color {
    componentStyle == .figmaPilot ? MoruPilotColor.accent : AppColor.orange350
  }

  private var unselectedColor: Color {
    componentStyle == .figmaPilot ? MoruPilotColor.textPrimary : AppColor.moruTextBody
  }

  private var minimumHeight: CGFloat {
    if componentStyle == .figmaPilot {
      return dynamicTypeSize.isAccessibilitySize ? 104 : 95
    }

    return dynamicTypeSize.isAccessibilitySize ? 72 : 65
  }
}
