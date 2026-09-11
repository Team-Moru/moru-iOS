//
//  ExitRoutineDialogView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import SwiftUI

/// 상단바 닫기(X)·종료 확인 다이얼로그. 문구만 다르고 결과는 둘 다 기록 저장이다.
struct ExitRoutineDialogView: View {
  let exit: RoutinePlayerViewModel.DialogState.Exit
  let onCancel: () -> Void
  let onConfirm: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var copy: RoutinePlayerDialogCopy {
    RoutinePlayerDialogCopy.exit(exit)
  }

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
