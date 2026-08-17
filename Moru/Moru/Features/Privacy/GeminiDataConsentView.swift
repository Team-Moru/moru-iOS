//
//  GeminiDataConsentView.swift
//  Moru
//

import SwiftUI

struct GeminiDataConsentView: View {
  @ObservedObject var consentStore: GeminiDataConsentStore
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MoruPilotSpacing.twenty) {
          Image(systemName: "sparkles")
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(MoruPilotColor.accent)
            .accessibilityHidden(true)

          Text("AI 데이터 처리 동의")
            .font(AppFont.pretendardBold(size: 24, relativeTo: .title2))
            .foregroundStyle(MoruPilotColor.textStrong)

          Text(
            "AI 맞춤 루틴 기능을 사용하면 입력한 루틴 제목·설명·단계 텍스트와 목표·키워드 등 요청 내용이 MORU 서버를 거쳐 Google Gemini API로 전송될 수 있어요. 이 요청으로 생성된 안내 텍스트는 Google TTS로 음성으로 만들어질 수 있고, 결과 오디오는 MORU 서버가 AWS S3에 저장해 앱에 제공할 수 있어요."
          )
          .font(AppFont.pretendardMedium(size: 16, relativeTo: .body))
          .foregroundStyle(MoruPilotColor.textPrimary)
          .fixedSize(horizontal: false, vertical: true)

          Text(
            "동의하지 않아도 로컬에서 루틴을 만들고 사용할 수 있어요. 다만 AI 처리로 이어질 수 있는 계정 동기화와 AI 루틴 추천은 전송하지 않아요."
          )
          .font(AppFont.pretendardMedium(size: 16, relativeTo: .body))
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)

          VStack(spacing: MoruPilotSpacing.twelve) {
            Button("동의하고 AI 기능 사용") {
              consentStore.grant()
              dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(MoruPilotColor.accent)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("gemini-consent.grant")

            Button("동의하지 않음") {
              consentStore.decline()
              dismiss()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("gemini-consent.decline")
          }
          .padding(.top, MoruPilotSpacing.eight)
        }
        .padding(MoruPilotSpacing.twenty)
      }
      .navigationTitle("AI 데이터 처리")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("나중에") {
            consentStore.dismissConsentChoices()
            dismiss()
          }
        }
      }
    }
    .accessibilityIdentifier("gemini-consent.sheet")
  }
}
