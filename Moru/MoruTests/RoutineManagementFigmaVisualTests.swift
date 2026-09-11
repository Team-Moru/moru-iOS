//
//  RoutineManagementFigmaVisualTests.swift
//  MoruTests
//
//  Created by Codex on 7/24/26.
//

import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Moru

@MainActor
final class RoutineManagementFigmaVisualTests: XCTestCase {
  func testRoutineManagementStatesRenderDeterministicallyAtReferenceVariants() throws {
    let outputDirectory = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["MORU_CAPTURE_OUTPUT_DIR"]
        ?? "/private/tmp/moru-figma-p3-after"
    )

    for state in RoutineManagementCaptureState.allCases {
      for variant in MoruVisualCaptureVariant.allCases {
        let first = try MoruVisualCaptureFixture.render(
          view(for: state),
          filename: "\(state.rawValue)-\(variant.rawValue).png",
          variant: variant,
          outputDirectory: outputDirectory
        )
        let second = try MoruVisualCaptureFixture.render(
          view(for: state),
          filename: "\(state.rawValue)-\(variant.rawValue)-repeat.png",
          variant: variant,
          outputDirectory: outputDirectory
        )

        XCTAssertEqual(first.size, CGSize(width: 393, height: 852))
        XCTAssertEqual(first.scale, 3)
        try assertVisualRepeat(first, second, "\(state.rawValue)-\(variant.rawValue)")
        try assertVisualBaseline(
          first,
          name: "\(state.rawValue)-\(variant.rawValue).png",
          expected: RoutineManagementVisualBaseline.hashes[
            "\(state.rawValue)-\(variant.rawValue).png"
          ],
          outputDirectory: outputDirectory
        )
      }
    }
  }

  func testRoutineManagementCopyMatchesApprovedFigmaLanguage() {
    XCTAssertEqual(RoutineManagementCopy.addRoutine, "새 루틴 추가하기")
    XCTAssertEqual(RoutineManagementCopy.addStep, "새 항목 추가하기")
    XCTAssertEqual(RoutineManagementCopy.createCompletion, "완료")
    XCTAssertEqual(RoutineManagementCopy.editCompletion, "저장")
    XCTAssertEqual(
      RoutineManagementCopy.routineMetadata(stepCount: 6, totalMinutes: 15),
      "6개 항목 ・15분"
    )
    XCTAssertEqual(
      RoutineManagementCopy.scheduleSummary(
        weekdays: Set(Weekday.weekdays),
        hour: 9,
        minute: 0
      ),
      "월 화 수 목 금・09시 00분"
    )
    XCTAssertEqual(
      RoutineManagementCopy.activeRoutineReplacementMessage(
        RoutineActivationConflictState(activeRoutineIDs: [UUID()])
      ),
      "다른 사용 중인 루틴이 1개 있어요.\n이 루틴으로 바꾸면 기존 루틴과 알람이 꺼져요.\n기존 요일 설정은 그대로 남아요."
    )
  }

  private func view(for state: RoutineManagementCaptureState) -> AnyView {
    switch state {
    case .routineList:
      AnyView(routineList(dependencies: regularDependencies))
    case .editorCollapsed:
      AnyView(editor(draft: regularDraft))
    case .editorSchedule:
      AnyView(editor(draft: regularDraft, initialScheduleExpanded: true))
    case .stepEdit:
      AnyView(
        bottomSheetStage(mediumHeight: 559) {
          RoutineStepAddSheet(
            initialStep: regularDraft.steps[1],
            onDelete: {}
          ) { _ in }
        }
      )
    case .deleteDialog:
      AnyView(
        dialogStage(
          title: "이 루틴을 삭제할까요?",
          message: "삭제한 루틴은\n되돌릴 수 없어요.",
          primaryTitle: "뒤로가기",
          secondaryTitle: "삭제하기"
        )
      )
    case .weekdayConflict:
      AnyView(
        dialogStage(
          title: "다른 루틴을 끌까요?",
          message: RoutineManagementCopy.activeRoutineReplacementMessage(
            RoutineActivationConflictState(activeRoutineIDs: [UUID()])
          ),
          primaryTitle: "취소",
          secondaryTitle: "변경하기"
        )
      )
    case .creationChoice:
      AnyView(
        bottomSheetStage(mediumHeight: 313) {
          RoutineCreationModeSelectionView { _ in }
        }
      )
    case .createEmpty:
      AnyView(editor(draft: emptyDraft))
    case .stepAdd:
      AnyView(
        bottomSheetStage(mediumHeight: 499) {
          RoutineStepAddSheet { _ in }
        }
      )
    case .editorLongKorean:
      AnyView(editor(draft: longKoreanDraft))
    case .listEmpty:
      AnyView(routineList(dependencies: emptyDependencies))
    case .listError:
      AnyView(routineList(dependencies: failureDependencies))
    }
  }

  private func routineList(dependencies: DependencyContainer) -> some View {
    MainTabView(
      home: AnyView(EmptyView()),
      routineSetting: RoutineSettingView(dependencies: dependencies),
      history: AnyView(EmptyView()),
      selection: .constant(.routine)
    )
  }

  private func editor(
    draft: RoutineDraftState,
    initialScheduleExpanded: Bool = false
  ) -> some View {
    RoutineEditorView(
      draft: draft,
      initialScheduleExpanded: initialScheduleExpanded,
      onSave: { _ in true },
      onReplaceActiveRoutine: { _ in true },
      onDelete: { _ in true }
    )
  }

  private func bottomSheetStage<Sheet: View>(
    mediumHeight: CGFloat,
    @ViewBuilder sheet: () -> Sheet
  ) -> some View {
    RoutineManagementBottomSheetCaptureStage(
      mediumHeight: mediumHeight,
      background: editor(draft: regularDraft),
      sheet: sheet()
    )
  }

  private func dialogStage(
    title: String,
    message: String,
    primaryTitle: String,
    secondaryTitle: String
  ) -> some View {
    ZStack {
      editor(draft: regularDraft)
        .blur(radius: 4)

      AppColor.grayBlack
        .opacity(0.22)
        .ignoresSafeArea()

      MoruDialog(
        title: title,
        message: message,
        primaryTitle: primaryTitle,
        secondaryTitle: secondaryTitle,
        primaryAction: {},
        secondaryAction: {}
      )
    }
  }

  private var regularDraft: RoutineDraftState {
    RoutineDraftState(
      id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
      routineID: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
      title: "활력 루틴",
      summary: "아침을 활기차게 시작하는 루틴",
      alarmScheduleID: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
      hour: 9,
      minute: 0,
      selectedWeekdays: Set(Weekday.weekdays),
      steps: [
        makeStep(index: 1, type: .confirm, title: "잠자리 정리하기", minutes: 1),
        makeStep(index: 2, type: .timer, title: "심호흡하며 명상하기", minutes: 3),
        makeStep(index: 3, type: .input, title: "오늘의 다짐 확언하기", minutes: 1),
        makeStep(index: 4, type: .timer, title: "가볍게 스트레칭하기", minutes: 3),
        makeStep(index: 5, type: .timer, title: "짧은 독서 몰입하기", minutes: 5),
        makeStep(index: 6, type: .input, title: "감정과 생각을 기록하기", minutes: 2),
      ]
    )
  }

  private var emptyDraft: RoutineDraftState {
    RoutineDraftState(
      id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
      title: "새 루틴",
      hour: 9,
      minute: 0,
      selectedWeekdays: Set(Weekday.weekdays)
    )
  }

  private var longKoreanDraft: RoutineDraftState {
    RoutineDraftState(
      id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
      routineID: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!,
      title: "상쾌한 아침을 차분하게 여는 스무 글자 이상 집중 루틴",
      summary: "한글 설명이 길어져도 항목과 완료 버튼을 가리지 않아야 해요.",
      hour: 9,
      minute: 0,
      selectedWeekdays: Set(Weekday.allCases),
      steps: [
        makeStep(
          index: 21,
          type: .confirm,
          title: "이불을 가지런히 정리하고 창문을 열어 환기하기",
          minutes: 1
        ),
        makeStep(
          index: 22,
          type: .timer,
          title: "호흡에 집중하며 몸과 마음을 천천히 깨우기",
          minutes: 5
        ),
      ]
    )
  }

  private func makeStep(
    index: Int,
    type: RoutineStepType,
    title: String,
    minutes: Int
  ) -> RoutineStepDraftState {
    RoutineStepDraftState(
      id: UUID(
        uuidString: String(
          format: "60000000-0000-0000-0000-%012d",
          index
        )
      )!,
      type: type,
      title: title,
      estimatedMinutes: minutes
    )
  }

  private var regularDependencies: DependencyContainer {
    makeDependencies(repository: MockRoutineRepository(routines: [
      makeRoutine(index: 1, name: "활력 루틴", isActive: true),
      makeRoutine(index: 2, name: "주말 루틴", isActive: false),
      makeRoutine(index: 3, name: "명상 루틴", isActive: false),
    ]))
  }

  private var emptyDependencies: DependencyContainer {
    makeDependencies(repository: MockRoutineRepository())
  }

  private var failureDependencies: DependencyContainer {
    makeDependencies(repository: RoutineManagementFailureRepository())
  }

  private func makeDependencies(
    repository: any RoutineRepository
  ) -> DependencyContainer {
    let profileRepository = MockLocalProfileRepository(
      profile: LocalProfile(displayName: "다인")
    )
    return DependencyContainer(
      routineRepository: repository,
      routineRunRepository: MockRoutineRunRepository(),
      localProfileRepository: profileRepository,
      onboardingRepository: MockOnboardingRepository(
        localProfileRepository: profileRepository,
        routineRepository: MockRoutineRepository()
      ),
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )
  }

  private func makeRoutine(
    index: Int,
    name: String,
    isActive: Bool
  ) -> Routine {
    let createdAt = Date(timeIntervalSince1970: 1_784_841_300 + Double(index))
    let stepCount = index == 1 ? 6 : 3
    let seconds = index == 1 ? 150 : 160
    return Routine(
      id: UUID(
        uuidString: String(
          format: "70000000-0000-0000-0000-%012d",
          index
        )
      )!,
      name: name,
      summary: "아침을 준비하는 루틴",
      steps: (0..<stepCount).map { stepIndex in
        RoutineStep(
          id: UUID(
            uuidString: String(
              format: "71000000-0000-0000-%04d-%012d",
              index,
              stepIndex + 1
            )
          )!,
          type: stepIndex.isMultiple(of: 2) ? .confirm : .timer,
          title: "루틴 단계 \(stepIndex + 1)",
          order: stepIndex,
          estimatedSeconds: seconds
        )
      },
      alarmSchedule: AlarmSchedule(
        id: UUID(
          uuidString: String(
            format: "72000000-0000-0000-0000-%012d",
            index
          )
        )!,
        hour: 9,
        minute: 0,
        weekdays: isActive ? Weekday.weekdays : [.saturday, .sunday]
      ),
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: createdAt
    )
  }
}

private struct RoutineManagementBottomSheetCaptureStage<
  Background: View,
  Sheet: View
>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let mediumHeight: CGFloat
  let background: Background
  let sheet: Sheet

  var body: some View {
    ZStack(alignment: .bottom) {
      background
        .blur(radius: 4)

      AppColor.grayBlack
        .opacity(0.22)
        .ignoresSafeArea()

      sheet
        .frame(
          height: dynamicTypeSize.isAccessibilitySize
            ? min(760, max(mediumHeight, 640))
            : mediumHeight,
          alignment: .top
        )
        .background(AppColor.grayWhite)
        .clipShape(
          UnevenRoundedRectangle(
            topLeadingRadius: AppRadius.lg,
            topTrailingRadius: AppRadius.lg
          )
        )
    }
  }
}

private enum RoutineManagementVisualBaseline {
  static let hashes: [String: String] = [
    "create-empty-light-AX3.png":
      "AAAAABAAyADIgBmEPYDAMMgALAJRA1gDJANMg2gDJgDZANmQpWLlZPIU8gDZSNl48GgIAz6j4ADAwMDAwQDgAA==",
    "create-empty-light-M.png":
      "AAAAACBAlgCHAJBAgAFIAwADYAMwAsgAwQKuBJAEyADIACICDwMEA4AAAAAAAAAAAAAAAAAAAADAAMCAwADAAA==",
    "creation-choice-light-AX3.png":
      "gACAAKACyAzETIzIzsgDMwyBDIAAEA2AHIAcAB4gTODMpsyGDcAMAA4ADwANAB2AHIAcAM4GzuZNwAzASpD+gA==",
    "creation-choice-light-M.png":
      "gACAAMBAggaCBpBAgALEAoAC5CKgAsAAyACKBIQEyADIAHEG0AwgQwMBAwAcANoG2oYdQAAA2QDKBshAIACgAA==",
    "delete-dialog-light-AX3.png":
      "gACAAKACyAzETIzIjsjBMMgAgA4ABxtHD+ccAx5nHqccpznHmJcGB44HgCcPBwcH2WrRaDIA8gDExMDE8gC4AA==",
    "delete-dialog-light-M.png":
      "gACAAMBAggaCBpBAgALEAoAC5CKgAsAAyACAFgyHHoeGhwaHEGcYZ5AP0Qy4BtANogLQBdANuAL5DMTEwMDAAA==",
    "editor-collapsed-light-AX3.png":
      "AAAAABAByAzMTCzJLsjBMMgAIgLIg0yDIwP1Q3EDeyMNgdgA2YDtYKVk82TyggSC2WnRaDKD8wDExMDE8wAyAA==",
    "editor-collapsed-light-M.png":
      "AAAAACBBkgaCBpBAgAHEAxADZiNSAsgAwQKuBJAEyADIAHAHUA00AlANUAc8B1ANIgJQDVANOAP5BMDEwMBgAA==",
    "editor-long-korean-light-AX3.png":
      "AAAAABAByAzMTCzJLsjBMMgAKoN3JEck7SdoM2yHTKPss+SDVudkZ2RjAgjZANlApZCXFNOB8yDExMDE8wAxwA==",
    "editor-long-korean-light-M.png":
      "AAAAACBBkgaCBpBAgIFUWRAD6sNQAsgAyIKTBJMEyADIMHEHUQ04ElANUCUjAw8DICNAAAAAAAPhAMDEwMAgAA==",
    "editor-schedule-light-AX3.png":
      "AAAAABAByAzMTCzJLsjBMMgAIgLIg0yDIwP1Q3EDeyMNgdgA2YDtYKVk80T8ygzIAzDMxOzA8yDExMDE9QDuyA==",
    "editor-schedule-light-M.png":
      "AAAAACBBkgaCBpBAgAHEAxADZiNSAsgAwQKuBIIkBNDEwMTAxMAk0BEq1VTVVMgRyABwD1ANMALxAMDEwMhAAA==",
    "list-empty-light-AX3.png":
      "AAAAAAAACADAAMQA5AA4AABABgAGAAaAOyA7ODKEMKZVGFWQe7B7sIU+Hscax4E+4AAAAAAAUSQsymzbrFrSJA==",
    "list-empty-light-M.png":
      "AAAAAAAAIACAAMgAyAAwAAAAAAAAAAMgDwANSFikGKYGk4MCwAAAAAAAAAAAAAAAAAAAAAAAUSQsymzbrFrSJA==",
    "list-error-light-AX3.png":
      "AAAAAAAACADAAMQA5AA4AAFAAwAGkAcQGSAZpGbAaNkJRAlAGsBa4ICeGwcbR4Ce4AAQAAAAUSQsymzbrFrSJA==",
    "list-error-light-M.png":
      "AAAAAAAAIACAAMgAyAAwAAAAAAAAAAMgEwAeZCyYBAIHA4MCwAAAAAAAAAAAAAAAAAAAAAAAUSQsymzbrFrSJA==",
    "routine-list-light-AX3.png":
      "AAAAAAAACADAAMQA5AA4AAIAykTKYNkY2RTTMNpwxOTAYMAQFgHoAOyAWxLdEF2AGmRAcEBwwCCsimzbrFrSZA==",
    "routine-list-light-M.png":
      "AAAAAAAAIACAAMgAyAAUAOEA4ADZGMg0yDDxCMACyAAmBlg4SDhCBIICWDjIOEIQgARPAEUAQQAsymzbrFrSJA==",
    "step-add-light-AX3.png":
      "gACAAKACyAzETIzIzsgBMwUBDoAMgAAQwADQAFwg1IKgAOAE4VjSuMK00ELAAMAA4yDDLNMg4EDAxMDA4ADwAA==",
    "step-add-light-M.png":
      "gACAAMBAggaCBpBAgALEAoAC5CKgAsAAyAMTAwIAAADAAMAAwALQhOMY4RjhGJAEgADDBMMEwIDAhMAEwACgAA==",
    "step-edit-light-AX3.png":
      "gACAAKACyAzETIzIzsgBMwRBDsAMwAAQwADQAHig+ILRkOBE4VjSuMK00ELAAMAA4yDDJPMA8gDEzMDE8gBwAA==",
    "step-edit-light-M.png":
      "gACAAMBAggaCBpBAgALEAoAC5AIBAwMBAgAAAMAAwADoAtCE4xjhGOMYkACAgMMkwwTgwMDEwEADAoMiwMDAAA==",
    "weekday-conflict-light-AX3.png":
      "gACAAKACyAzMTIzOAAedJ51nDAcNhx1nGUcxUzlTKXM2YzZjhocbQ5tHnKcUpwIHgweAJw0HjgbAzMDE8gC4AA==",
    "weekday-conflict-light-M.png":
      "gACAAMBAggaCBpBAgALEAoAC5CKgAsAAyASQNg5HHwe9IzrjBgcYZ5Fn0Ry4BtANogLQBdANuAL4DMDE4MjAAA==",
  ]
}

private enum RoutineManagementCaptureState: String, CaseIterable {
  case routineList = "routine-list"
  case editorCollapsed = "editor-collapsed"
  case editorSchedule = "editor-schedule"
  case stepEdit = "step-edit"
  case deleteDialog = "delete-dialog"
  case weekdayConflict = "weekday-conflict"
  case creationChoice = "creation-choice"
  case createEmpty = "create-empty"
  case stepAdd = "step-add"
  case editorLongKorean = "editor-long-korean"
  case listEmpty = "list-empty"
  case listError = "list-error"
}

@MainActor
private final class RoutineManagementFailureRepository: RoutineRepository {
  private enum Failure: Error {
    case unavailable
  }

  func fetchRoutines() throws -> [Routine] {
    throw Failure.unavailable
  }

  func fetchActiveRoutines() throws -> [Routine] {
    throw Failure.unavailable
  }

  func routine(id: UUID) throws -> Routine? {
    throw Failure.unavailable
  }

  func saveRoutine(_ routine: Routine) throws {
    throw Failure.unavailable
  }

  func saveRoutines(_ routines: [Routine]) throws {
    throw Failure.unavailable
  }

  func updateRoutineActivation(id: UUID, isActive: Bool) throws {
    throw Failure.unavailable
  }

  func deleteRoutine(id: UUID) throws {
    throw Failure.unavailable
  }
}
