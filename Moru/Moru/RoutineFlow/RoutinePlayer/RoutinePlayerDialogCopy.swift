//
//  RoutinePlayerDialogCopy.swift
//  Moru
//

import Foundation

/// 루틴 플레이어 다이얼로그 문구. 뷰가 아니라 여기서 단언한다.
nonisolated struct RoutinePlayerDialogCopy: Equatable {
  let title: String
  let message: String
  /// 다이얼로그를 닫고 루틴으로 돌아가는 버튼
  let cancelTitle: String
  /// 다이얼로그가 묻는 행동을 실행하는 버튼
  let confirmTitle: String

  /// 상단바 "종료": 지금까지의 결과를 저장하고 완료 요약 화면으로 간다.
  static let endRoutine = RoutinePlayerDialogCopy(
    title: "루틴을 종료할까요?",
    message: """
    지금까지 완료한 항목만 저장돼요.
    나머지는 미완료로 기록됩니다.
    """,
    cancelTitle: "계속하기",
    confirmTitle: "종료하기"
  )

  /// 상단바 "닫기"(X): 지금까지의 결과를 저장하고 요약 없이 홈으로 돌아간다.
  static let closeRoutine = RoutinePlayerDialogCopy(
    title: "루틴을 닫을까요?",
    message: """
    지금까지의 진행은 기록에 남고
    홈으로 돌아가요.
    """,
    cancelTitle: "계속하기",
    confirmTitle: "닫기"
  )

  /// 건너뛰기 footer
  static let skipStep = RoutinePlayerDialogCopy(
    title: "이 항목을 건너뛸까요?",
    message: """
    건너뛰면 현재 루틴은 미완료로 기록돼요.
    다음 루틴으로 넘어갈게요.
    """,
    cancelTitle: "계속하기",
    confirmTitle: "건너뛰기"
  )

  /// 저장에 실패한 기록을 버리고 나갈지 묻는다.
  static let discardUnsavedRun = RoutinePlayerDialogCopy(
    title: "기록 없이 나갈까요?",
    message: """
    저장하지 못한 오늘 기록은 남지 않아요.
    다시 시도하면 저장할 수 있어요.
    """,
    cancelTitle: "돌아가기",
    confirmTitle: "기록 없이 나가기"
  )

  static func exit(
    _ exit: RoutinePlayerViewModel.DialogState.Exit
  ) -> RoutinePlayerDialogCopy {
    switch exit {
    case .endedEarly:
      return endRoutine
    case .userDismissed:
      return closeRoutine
    }
  }
}
