//
//  DiscardUnsavedRunDialogView.swift
//  Moru
//

import SwiftUI

struct DiscardUnsavedRunDialogView: View {
  let onCancel: () -> Void
  let onConfirm: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private let copy = RoutinePlayerDialogCopy.discardUnsavedRun

  var body: some View {
    ZStack {
      Color.black.opacity(0.35)
        .ignoresSafeArea()
        .onTapGesture {
          onCancel()
        }

      MoruDialog(
        title: copy.title,
        message: copy.message,
        primaryTitle: copy.cancelTitle,
        secondaryTitle: copy.confirmTitle,
        primaryAction: onCancel,
        secondaryAction: onConfirm
      )
      .offset(y: dynamicTypeSize.isAccessibilitySize ? 0 : -12)
    }
    .accessibilityAddTraits(.isModal)
  }
}
