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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    selection: Binding<MoruTabItem>,
    items: [MoruTabItem] = MoruTabItem.allCases
  ) {
    _selection = selection
    self.items = items
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        ForEach(items) { item in
          tabButton(for: item)
            .frame(maxWidth: .infinity)
        }
      }
      .padding(.horizontal, MoruSpacing.twenty)

      Spacer(minLength: 0)
    }
    .padding(.top, dynamicTypeSize.isAccessibilitySize ? 12 : 15)
    .frame(maxWidth: .infinity)
    .frame(height: minimumHeight)
    .background {
      AppColor.grayWhite
        .opacity(0.7)
        .background(.ultraThinMaterial)
        .ignoresSafeArea(edges: .bottom)
    }
    .shadow(
      color: MoruColor.tabBarShadow,
      radius: 10,
      x: 0,
      y: -2
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(Self.accessibilityIdentifier)
  }

  private var selectedColor: Color {
    MoruColor.accent
  }

  private var unselectedColor: Color {
    MoruColor.textPrimary
  }

  private var minimumHeight: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 70 : 61
  }

  private func tabButton(for item: MoruTabItem) -> some View {
    Button {
      selection = item
    } label: {
      VStack(spacing: MoruSpacing.four) {
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
            .moruTextStyle(.c2.weight(.regular))
            .foregroundStyle(
              selection == item ? selectedColor : unselectedColor
            )
        }
      }
      .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 52 : 45)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(item.title)
    .accessibilityAddTraits(selection == item ? .isSelected : [])
    .accessibilityIdentifier(Self.accessibilityIdentifier(for: item))
  }
}
