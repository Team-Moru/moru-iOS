//
//  MyPageView.swift
//  Moru
//
//  Created by Codex on 7/13/26.
//

import SwiftUI

struct MyPageView: View {
  private let onLocalDataReset: () -> Void

  @State private var viewModel: MyPageViewModel
  @State private var isResetDialogPresented = false
  @State private var isVoiceSettingPresented = false
  @State private var isProfileEditPresented = false

  init(
    dependencies: DependencyContainer,
    onLocalDataReset: @escaping () -> Void
  ) {
    self.onLocalDataReset = onLocalDataReset
    _viewModel = State(initialValue: MyPageViewModel(dependencies: dependencies))
  }

  var body: some View {
    NavigationStack {
      ZStack {
        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: AppSpacing.xxl) {
            Text("설정")
              .font(AppFont.heading1Bold)
              .foregroundStyle(AppColor.moruTextPrimary)
              .padding(.top, AppSpacing.fiftySix)

            ProfileSummaryCard(
              displayName: viewModel.state.displayName,
              action: {
                isProfileEditPresented = true
              }
            )

            VStack(alignment: .leading, spacing: AppSpacing.md) {
              MyPageSectionHeader(title: "음성 설정")
              MyPageMenuRow(
                title: viewModel.state.selectedVoice.displayName,
                action: {
                  isVoiceSettingPresented = true
                }
              )
            }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
              MyPageSectionHeader(title: "데이터")
              MyPageMenuRow(
                title: "로컬 데이터 초기화",
                subtitle: "프로필, 음성 설정, 루틴, 수행 기록을 기기에서 삭제합니다.",
                titleColor: AppColor.orange500,
                action: {
                  isResetDialogPresented = true
                }
              )
            }

            if let errorMessage = viewModel.state.errorMessage {
              Text(errorMessage)
                .font(AppFont.caption1Medium)
                .foregroundStyle(AppColor.orange500)
            }
          }
          .padding(.horizontal, AppSpacing.screenHorizontal)
          .padding(.bottom, 120)
        }

        if isResetDialogPresented {
          resetDialogOverlay
        }
      }
      .background(pageBackground.ignoresSafeArea())
      .navigationDestination(isPresented: $isVoiceSettingPresented) {
        VoiceSettingView(viewModel: viewModel)
      }
      .navigationDestination(isPresented: $isProfileEditPresented) {
        ProfileEditView(viewModel: viewModel)
      }
      .toolbar(.hidden, for: .navigationBar)
      .task {
        viewModel.load()
      }
    }
  }

  private var resetDialogOverlay: some View {
    ZStack {
      AppColor.grayBlack.opacity(0.35)
        .ignoresSafeArea()
        .onTapGesture {
          isResetDialogPresented = false
        }

      MoruDialog(
        title: "로컬 데이터를 초기화할까요?",
        message: "앱을 처음 설치한 상태로 되돌리고 온보딩으로 이동합니다.",
        primaryTitle: "뒤로가기",
        secondaryTitle: "초기화",
        primaryAction: {
          isResetDialogPresented = false
        },
        secondaryAction: {
          isResetDialogPresented = false
          if viewModel.resetLocalData() {
            onLocalDataReset()
          }
        }
      )
    }
  }

  private var pageBackground: LinearGradient {
    LinearGradient(
      stops: [
        Gradient.Stop(color: AppColor.gray100, location: 0),
        Gradient.Stop(color: AppColor.grayWhite, location: 1),
      ],
      startPoint: UnitPoint(x: 0.5, y: 0),
      endPoint: UnitPoint(x: 0.5, y: 1)
    )
  }
}

#if DEBUG
#Preview {
  MyPageView(dependencies: .homePreview) {}
}
#endif
