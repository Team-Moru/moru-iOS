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
            "AI 맞춤 루틴 기능을 사용하면 입력한 사용자 답변, "
              + "루틴 제목·설명·단계 텍스트와 "
              + "목표·키워드 등 요청 내용이 MORU 서버를 거쳐 "
              + "Google Gemini API로 전송될 수 있어요. "
              + "이메일, 소셜 계정 ID, MORU 회원 ID, "
              + "원본 음성 파일은 Gemini에 보내지 않아요."
          )
          .font(AppFont.pretendardMedium(size: 16, relativeTo: .body))
          .foregroundStyle(MoruPilotColor.textPrimary)
          .fixedSize(horizontal: false, vertical: true)

          Text(
            "Gemini 무료 등급에서는 위 입력과 생성 응답이 "
              + "Google의 제품·서비스 및 머신러닝 기술 개선에 "
              + "사용될 수 있고, 품질 검토를 위해 사람이 검토할 수 있어요. "
              + "Google은 남용 탐지 로그를 최대 55일 보관할 수 있어요."
          )
          .font(AppFont.pretendardMedium(size: 16, relativeTo: .body))
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)

          Text(
            "AI가 생성한 안내 문구와 선택한 음성 코드는 "
              + "Google Cloud TTS에 전달될 수 있어요. 생성 MP3는 "
              + "AWS S3에 저장되고, 앱에는 최대 60분 동안 "
              + "유효한 링크로 제공돼요. MORU 운영 기준상 "
              + "TTS에 전달한 텍스트와 생성 음성은 학습용으로 "
              + "별도 기록하거나 재사용하지 않아요."
          )
          .font(AppFont.pretendardMedium(size: 16, relativeTo: .body))
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)

          Text(
            "동의하지 않거나 철회하면 Gemini 처리를 유발할 수 있는 "
              + "새 요청과 해당 자동 재시도를 전송하지 않아요. "
              + "일반 계정 동기화와 로컬 루틴 기능은 AI 동의와 "
              + "별개로 사용할 수 있어요."
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
