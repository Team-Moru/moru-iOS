//
//  OnboardingCopy.swift
//  Moru
//
//  Created by Codex on 7/24/26.
//

import Foundation

enum OnboardingCopy {
  static let experienceSubtitle = "맞춤 루틴을 설정해드릴게요"
  static let freeformSubtitle =
    "자연어로 편하게 입력하면 로컬 템플릿으로 정리해드려요"
  static let organizingTitle = "루틴을 정리하고 있어요"
  static let organizingSubtitle = "잠시만 기다려주세요 ∙∙∙"
  static let reviewTitle = "정리된\n루틴이에요"
  static let voiceSubtitle =
    "아침마다 들을 앱 내장 목소리예요. 들어보고 골라보세요."

  static let experienceDescriptions: [RoutineExperience: String] = [
    .firstTime: "루틴을 경험해본 적 없어요",
    .wantsRecommendation: "어떤 루틴이 좋을지 모르겠어요",
    .hasRoutine: "이미 루틴이 있어요",
  ]

  static let goalDescriptions: [String: String] = [
    "energy": "에너지 넘치는 하루 시작",
    "health": "몸과 마음을 챙기는 루틴",
    "mind": "차분하고 평온한 아침",
    "habit": "꾸준한 생활 루틴 만들기",
  ]

  static let voiceDescriptions: [String: String] = [
    VoiceProfile.aoede.id: "따뜻한 친구",
    VoiceProfile.charon.id: "차분한 동반자",
    VoiceProfile.kore.id: "활기찬 응원자",
    VoiceProfile.orus.id: "편안한 가족 같은 목소리",
  ]

  static func experienceDescription(
    for experience: RoutineExperience
  ) -> String {
    experienceDescriptions[experience] ?? ""
  }

  static func goalDescription(for tag: String) -> String {
    goalDescriptions[tag] ?? ""
  }

  static func voiceDescription(for voice: VoiceProfile) -> String {
    voiceDescriptions[voice.id] ?? "앱 내장 목소리"
  }

  static func voiceCTA(for voice: VoiceProfile) -> String {
    "‘\(voice.displayName)’로 코칭받기"
  }
}
