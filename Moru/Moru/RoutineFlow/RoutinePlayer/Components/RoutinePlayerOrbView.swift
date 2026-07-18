//
//  RoutinePlayerOrbView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import SwiftUI

struct RoutinePlayerOrbView: View {
    var body: some View {
        Image(AppImage.moruImageHalo)
            .resizable()
            .scaledToFit()
            .frame(width: 296, height: 296)
            .accessibilityHidden(true)
    }
}
