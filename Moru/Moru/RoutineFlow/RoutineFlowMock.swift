//
//  RoutineFlowMock.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//
import Foundation

#if DEBUG
extension Routine {
    static let mockMorningRoutine = Routine(
        name: "활력 루틴",
        summary: "아침을 깨우는 루틴",
        goalTags: ["아침", "건강"],
        steps: [
            RoutineStep(
                type: .confirm,
                title: "잠자리 정리하기",
                instruction: "이불과 베개를 정리해 주세요.",
                order: 0
            ),
            RoutineStep(
                type: .timer,
                title: "스트레칭하기",
                instruction: "가볍게 몸을 풀어주세요.",
                order: 1,
                estimatedSeconds: 10
            ),
            RoutineStep(
                type: .input,
                title: "오늘의 다짐 말하기",
                instruction: "오늘 이루고 싶은 일을 말해주세요.",
                order: 2
            )
        ]
    )
}
#endif
