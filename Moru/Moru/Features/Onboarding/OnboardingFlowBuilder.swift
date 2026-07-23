//
//  OnboardingFlowBuilder.swift
//  Moru
//
//  Created by Codex on 7/13/26.
//

import SwiftUI

typealias OnboardingCompletionHandler = @MainActor (_ routineID: UUID) -> Void

@MainActor
protocol OnboardingFlowBuilding: AnyObject {
  func make(
    onCompleted: @escaping OnboardingCompletionHandler
  ) -> AnyView
}
@MainActor
final class DefaultOnboardingFlowBuilder: OnboardingFlowBuilding {
  private let routineSuggestionService: any RoutineSuggestionService
  private let completeOnboardingUseCase: any CompleteOnboardingUseCaseProtocol
  private let voicePreviewPlayer: any VoicePreviewPlaying

  init(
    routineSuggestionService: any RoutineSuggestionService,
    completeOnboardingUseCase: any CompleteOnboardingUseCaseProtocol,
    voicePreviewPlayer: any VoicePreviewPlaying
  ) {
    self.routineSuggestionService = routineSuggestionService
    self.completeOnboardingUseCase = completeOnboardingUseCase
    self.voicePreviewPlayer = voicePreviewPlayer
  }

  func make(
    onCompleted: @escaping OnboardingCompletionHandler
  ) -> AnyView {
    AnyView(
      OnboardingFlowView(
        viewModel: OnboardingViewModel(
          routineSuggestionService: routineSuggestionService,
          completeOnboardingUseCase: completeOnboardingUseCase,
          voicePreviewPlayer: voicePreviewPlayer,
          onCompleted: onCompleted
        )
      )
    )
  }
}
