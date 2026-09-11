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
                        .padding(.vertical, 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)

            MoruButton("다시 알림 설정") {
                onConfirm(selectedMinutes)
            }
            .padding(.horizontal, 20)

            MoruButton("취소", style: .secondary) {
                onCancel()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 21)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
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
