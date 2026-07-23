//
//  RoutineListFigmaVisualTests.swift
//  MoruTests
//
//  Created by Codex on 7/24/26.
//

import Foundation
import SwiftUI
import XCTest
@testable import Moru

@MainActor
final class RoutineListFigmaVisualTests: XCTestCase {
  func testRoutineListStatesRenderDeterministicallyAtReferenceVariants() throws {
    let environment = ProcessInfo.processInfo.environment
    let phase = environment["MORU_ROUTINE_CAPTURE_PHASE"] ?? "after"
    let outputDirectory = URL(
      fileURLWithPath: environment["MORU_CAPTURE_OUTPUT_DIR"]
        ?? "/private/tmp/moru-figma-d1-\(phase)"
    )

    for state in RoutineListCaptureState.allCases {
      for variant in MoruVisualCaptureVariant.allCases {
        let filename = "\(state.rawValue)-\(variant.rawValue).png"
        let first = try MoruVisualCaptureFixture.render(
          routineList(for: state),
          filename: filename,
          variant: variant,
          outputDirectory: outputDirectory
        )
        let second = try MoruVisualCaptureFixture.render(
          routineList(for: state),
          filename: "\(state.rawValue)-\(variant.rawValue)-repeat.png",
          variant: variant,
          outputDirectory: outputDirectory
        )

        XCTAssertEqual(first.size, CGSize(width: 393, height: 852))
        XCTAssertEqual(first.scale, 3)
        XCTAssertEqual(first.pngData(), second.pngData())
      }
    }
  }

  private func routineList(
    for state: RoutineListCaptureState
  ) -> some View {
    MainTabView(
      home: AnyView(EmptyView()),
      routineSetting: RoutineSettingView(dependencies: dependencies(for: state)),
      history: AnyView(EmptyView()),
      selection: .constant(.routine),
      historyReloadToken: 0
    )
  }

  private func dependencies(
    for state: RoutineListCaptureState
  ) -> DependencyContainer {
    switch state {
    case .normal:
      return makeDependencies(routines: [
        makeRoutine(index: 1, name: "활력 루틴", stepCount: 6, isActive: true),
        makeRoutine(index: 2, name: "주말 루틴", stepCount: 3, isActive: false),
        makeRoutine(index: 3, name: "명상 루틴", stepCount: 3, isActive: false),
      ])
    case .empty:
      return makeDependencies(routines: [])
    case .partialEmpty:
      return makeDependencies(routines: [
        makeRoutine(index: 1, name: "활력 루틴", stepCount: 6, isActive: true),
      ])
    case .alarmWarning:
      let routine = makeRoutine(
        index: 1,
        name: "활력 루틴",
        stepCount: 6,
        isActive: true
      )
      let request = try! XCTUnwrap(AlarmScheduleRequest(routine: routine))
      let record = AlarmDeliveryRecord(
        request: request,
        backend: nil,
        state: .authorizationRequired,
        platformIdentifiers: [],
        lastErrorMessage: "authorization-required",
        updatedAt: Date(timeIntervalSince1970: 1_784_841_300)
      )
      return makeDependencies(
        routines: [routine],
        alarmStateRepository: RoutineListAlarmStateRepository(
          records: [record.scheduleID: record]
        )
      )
    case .longKorean:
      return makeDependencies(routines: [
        makeRoutine(
          index: 1,
          name: "상쾌한 아침을 차분하게 여는 스무 글자 이상 집중 루틴",
          stepCount: 8,
          isActive: true
        ),
        makeRoutine(
          index: 2,
          name: "잠들기 전 몸과 마음을 정돈하는 긴 저녁 루틴",
          stepCount: 7,
          isActive: false
        ),
      ])
    }
  }

  private func makeDependencies(
    routines: [Routine],
    alarmStateRepository: (any AlarmPlatformStateRepository)? = nil
  ) -> DependencyContainer {
    let routineRepository = MockRoutineRepository(routines: routines)
    let localProfileRepository = MockLocalProfileRepository(
      profile: LocalProfile(displayName: "다인")
    )

    return DependencyContainer(
      routineRepository: routineRepository,
      routineRunRepository: MockRoutineRunRepository(),
      localProfileRepository: localProfileRepository,
      onboardingRepository: MockOnboardingRepository(
        localProfileRepository: localProfileRepository,
        routineRepository: routineRepository
      ),
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      alarmPlatformStateRepository: alarmStateRepository
    )
  }

  private func makeRoutine(
    index: Int,
    name: String,
    stepCount: Int,
    isActive: Bool
  ) -> Routine {
    let routineID = UUID(
      uuidString: String(
        format: "00000000-0000-0000-0000-%012d",
        index
      )
    )!
    let scheduleID = UUID(
      uuidString: String(
        format: "10000000-0000-0000-0000-%012d",
        index
      )
    )!
    let createdAt = Date(timeIntervalSince1970: 1_784_841_300 + Double(index))
    let steps = (0..<stepCount).map { stepIndex in
      RoutineStep(
        id: UUID(
          uuidString: String(
            format: "20000000-0000-0000-%04d-%012d",
            index,
            stepIndex + 1
          )
        )!,
        type: stepIndex.isMultiple(of: 2) ? .confirm : .timer,
        title: "루틴 단계 \(stepIndex + 1)",
        order: stepIndex,
        estimatedSeconds: index == 1 ? 150 : 160
      )
    }

    return Routine(
      id: routineID,
      name: name,
      summary: "두 줄까지 안전하게 표시되는 루틴 설명",
      steps: steps,
      alarmSchedule: AlarmSchedule(
        id: scheduleID,
        hour: 6 + index,
        minute: 15,
        weekdays: isActive ? Weekday.weekdays : [.saturday, .sunday]
      ),
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: createdAt
    )
  }
}

private enum RoutineListCaptureState: String, CaseIterable {
  case normal
  case empty
  case partialEmpty = "partial-empty"
  case alarmWarning = "alarm-warning"
  case longKorean = "long-korean"
}

@MainActor
private final class RoutineListAlarmStateRepository:
  AlarmPlatformStateRepository {
  private var records: [UUID: AlarmDeliveryRecord]
  private var snoozedAlarms: [UUID: SnoozedAlarmRecord] = [:]

  init(records: [UUID: AlarmDeliveryRecord]) {
    self.records = records
  }

  func fetchRecords() throws -> [AlarmDeliveryRecord] {
    Array(records.values)
  }

  func record(scheduleID: UUID) throws -> AlarmDeliveryRecord? {
    records[scheduleID]
  }

  func saveRecord(_ record: AlarmDeliveryRecord) throws {
    records[record.scheduleID] = record
  }

  func deleteRecord(scheduleID: UUID) throws {
    records[scheduleID] = nil
  }

  func deleteAllRecords() throws {
    records.removeAll()
  }

  func fetchSnoozedAlarms() throws -> [SnoozedAlarmRecord] {
    Array(snoozedAlarms.values)
  }

  func saveSnoozedAlarm(_ record: SnoozedAlarmRecord) throws {
    snoozedAlarms[record.id] = record
  }

  func replaceSnoozedAlarm(
    scheduleID: UUID,
    with record: SnoozedAlarmRecord
  ) throws {
    snoozedAlarms = snoozedAlarms.filter {
      $0.value.scheduleID != scheduleID
    }
    snoozedAlarms[record.id] = record
  }

  func deleteSnoozedAlarm(id: UUID) throws {
    snoozedAlarms[id] = nil
  }

  func deleteAllSnoozedAlarms() throws {
    snoozedAlarms.removeAll()
  }
}
