//
//  ActiveRoutineWeekdayPolicy.swift
//  Moru
//

import Foundation

/// "활성 루틴끼리 요일이 겹치면 안 된다"는 불변식 하나를 담는 곳.
///
/// 예전에는 같은 규칙이 두 군데에 각자 구현돼 있었다. UseCase는 저장 전에
/// 충돌하는 루틴을 찾아 사용자에게 교체를 물었고(`RoutineSettingUseCase`),
/// 리포지토리는 저장 트랜잭션 안에서 마지막 방어선으로 다시 검사했다
/// (`SwiftDataRoutineRepository`). 지금은 동작이 같지만, 한쪽만 고치면
/// **UI는 통과시키는데 저장이 throw하는** 상태가 된다. 사용자에게는
/// "저장 버튼이 그냥 안 먹는" 것으로 보인다.
///
/// 두 호출자는 서로 다른 질문을 한다. UseCase는 "누구와 겹치나"(교체 대상을
/// 보여줘야 하므로 ID가 필요)를, 리포지토리는 "겹치는 게 있나 없나"를 묻는다.
/// 그래서 함수는 둘이되 판단 기준은 하나다.
///
/// 저장 트랜잭션 자체는 리포지토리에 남는다. 여기로 옮긴 것은 정책뿐이라
/// 이제 저장소를 띄우지 않고도 규칙을 검증할 수 있다.
enum ActiveRoutineWeekdayPolicy {
  /// 주어진 요일과 겹치는 **다른** 활성 루틴들의 ID.
  ///
  /// - Parameters:
  ///   - weekdays: 새로 차지하려는 요일.
  ///   - routineID: 자기 자신. 편집 중인 루틴은 자신과 충돌하지 않는다.
  ///   - routines: 검사 대상 전체.
  static func conflictingRoutineIDs(
    occupying weekdays: Set<Weekday>,
    excluding routineID: UUID?,
    among routines: [Routine]
  ) -> Set<UUID> {
    guard !weekdays.isEmpty else {
      return []
    }

    return routines.reduce(into: Set<UUID>()) { result, routine in
      guard routine.id != routineID,
            !scheduledWeekdays(of: routine).isDisjoint(with: weekdays) else {
        return
      }

      result.insert(routine.id)
    }
  }

  /// 저장하려는 집합이 불변식을 지키는지. 지키지 않으면 던진다.
  static func validate(_ routines: [Routine]) throws {
    var occupied: Set<Weekday> = []
    for routine in routines {
      let weekdays = scheduledWeekdays(of: routine)
      guard occupied.isDisjoint(with: weekdays) else {
        throw RepositoryContractError.overlappingActiveRoutineWeekdays
      }

      occupied.formUnion(weekdays)
    }
  }

  /// 루틴이 실제로 차지하는 요일. 비활성 루틴과 알람 없는 루틴은 아무 요일도
  /// 차지하지 않으므로 누구와도 충돌하지 않는다.
  static func scheduledWeekdays(of routine: Routine) -> Set<Weekday> {
    guard routine.isActive, let schedule = routine.alarmSchedule else {
      return []
    }

    return Set(schedule.weekdays)
  }
}
