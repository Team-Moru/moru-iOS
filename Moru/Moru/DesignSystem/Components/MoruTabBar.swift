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
                selection == item ? AppColor.orange350 : AppColor.moruTextBody
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
                    ? AppFont.pretendardMedium(size: 12)
                    : AppFont.pretendardRegular(size: 12)
                )
                .foregroundStyle(
                  selection == item ? AppColor.orange350 : AppColor.moruTextBody
                )
            }
          }
          .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 52 : 45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selection == item ? .isSelected : [])
        .accessibilityValue(selection == item ? "선택됨" : "")
        .accessibilityIdentifier(Self.accessibilityIdentifier(for: item))
      }
    }
    .frame(maxWidth: .infinity, minHeight: 45)
    .padding(.horizontal, AppSpacing.screenHorizontal)
    .frame(
      maxWidth: .infinity,
      minHeight: dynamicTypeSize.isAccessibilitySize ? 72 : 95
    )
    .background(AppColor.grayWhite)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(Self.accessibilityIdentifier)
  }
}
