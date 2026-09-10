//
//  RoutinePlayerDialogCopy.swift
//  Moru
//

import Foundation

/// 루틴 플레이어 다이얼로그 문구. 뷰가 아니라 여기서 단언한다.
struct RoutinePlayerDialogCopy: Equatable {
  let title: String
  let message: String
  /// 다이얼로그를 닫고 루틴으로 돌아가는 버튼
  let cancelTitle: String
  /// 다이얼로그가 묻는 행동을 실행하는 버튼
  let confirmTitle: String

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
}
