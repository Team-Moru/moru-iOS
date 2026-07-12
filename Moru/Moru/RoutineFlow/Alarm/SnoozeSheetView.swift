//
//  SnoozeSheetView.swift
//  Moru
//
//  Created by 김승겸 on 7/7/26.
//

import SwiftUI

struct SnoozeSheetView: View {
    @State private var selectedMinutes: Int

    let onConfirm: (Int) -> Void
    let onCancel: () -> Void

    private let options = [5, 10, 15, 30]

    init(
        selectedMinutes: Int = 5,
        onConfirm: @escaping (Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _selectedMinutes = State(initialValue: selectedMinutes)
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
//            Capsule()
//                .fill(AppColor.gray200)
//                .frame(width: 48, height: 4)
//                .padding(.vertical, 16)

            Text("다시 알림")
                .font(AppFont.pretendardSemiBold(size: 18))
                .foregroundStyle(AppColor.gray550)
                .padding(.top, 32)
                .padding(.bottom, 12)

            Divider()
                .background(AppColor.gray150)

            VStack(spacing: 0) {
                ForEach(options, id: \.self) { minutes in
                    Button {
                        selectedMinutes = minutes
                    } label: {
                        HStack {
                            Spacer()

                            Text("\(minutes)분 후")
                                .font(AppFont.body1NormalMedium)
                                .foregroundStyle(
                                    selectedMinutes == minutes
                                        ? AppColor.gray550
                                        : AppColor.gray400
                                )

                            Spacer()
                        }
                        .frame(height: 70)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(minutes)분 후 다시 알림")
                    .accessibilityValue(
                        selectedMinutes == minutes
                            ? "선택됨"
                            : "선택 안 됨"
                    )
                }
            }

            Spacer(minLength: 20)

            Button {
                onConfirm(selectedMinutes)
            } label: {
                Text("다시 알림 설정")
                    .font(AppFont.body1NormalSemiBold)
                    .foregroundStyle(AppColor.grayWhite)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(AppColor.orange350)
                    .cornerRadius(100)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)

            Button {
                onCancel()
            } label: {
                Text("취소")
                    .font(AppFont.body1NormalSemiBold)
                    .foregroundStyle(AppColor.gray600)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 100)
                            .stroke(AppColor.gray150, lineWidth: 1)
                    )
                    .background(AppColor.grayWhite)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 21)
        }
        .background(AppColor.grayWhite)
    }
}

#Preview("Snooze Sheet") {
    SnoozeSheetView(
        selectedMinutes: 5,
        onConfirm: { _ in },
        onCancel: {}
    )
}
