//
//  MoruVisualCaptureFixture.swift
//  MoruTests
//
//  Created by Codex on 7/24/26.
//

import Foundation
import SwiftUI
import UIKit
import XCTest

enum MoruVisualCaptureVariant: String, CaseIterable {
  case lightMedium = "light-M"
  case lightAccessibility3 = "light-AX3"

  var dynamicTypeSize: DynamicTypeSize {
    switch self {
    case .lightMedium:
      .medium
    case .lightAccessibility3:
      .accessibility3
    }
  }
}

struct MoruVisualCaptureConfiguration {
  static let iPhone16 = MoruVisualCaptureConfiguration()

  let size: CGSize
  let scale: CGFloat
  let locale: Locale
  let timeZone: TimeZone
  let calendar: Calendar
  let now: Date
  let colorScheme: ColorScheme
  let userInterfaceStyle: UIUserInterfaceStyle

  init(
    size: CGSize = CGSize(width: 393, height: 852),
    scale: CGFloat = 3,
    locale: Locale = Locale(identifier: "ko_KR"),
    timeZone: TimeZone = TimeZone(identifier: "Asia/Seoul")!,
    now: Date = Date(timeIntervalSince1970: 1_784_841_300),
    colorScheme: ColorScheme = .light,
    userInterfaceStyle: UIUserInterfaceStyle = .light
  ) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    calendar.timeZone = timeZone

    self.size = size
    self.scale = scale
    self.locale = locale
    self.timeZone = timeZone
    self.calendar = calendar
    self.now = now
    self.colorScheme = colorScheme
    self.userInterfaceStyle = userInterfaceStyle
  }
}

@MainActor
enum MoruVisualCaptureFixture {
  static func render<Content: View>(
    _ content: Content,
    filename: String,
    variant: MoruVisualCaptureVariant,
    outputDirectory: URL,
    configuration: MoruVisualCaptureConfiguration = .iPhone16
  ) throws -> UIImage {
    let renderedContent = content
      .environment(\.dynamicTypeSize, variant.dynamicTypeSize)
      .environment(\.locale, configuration.locale)
      .environment(\.calendar, configuration.calendar)
      .environment(\.timeZone, configuration.timeZone)
      .preferredColorScheme(configuration.colorScheme)

    let windowScene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    )
    let bounds = CGRect(origin: .zero, size: configuration.size)
    let hostingController = UIHostingController(rootView: renderedContent)
    let window = UIWindow(windowScene: windowScene)
    window.frame = bounds
    window.overrideUserInterfaceStyle = configuration.userInterfaceStyle
    window.rootViewController = hostingController
    window.makeKeyAndVisible()

    let animationsWereEnabled = UIView.areAnimationsEnabled
    UIView.setAnimationsEnabled(false)
    defer {
      UIView.setAnimationsEnabled(animationsWereEnabled)
      window.isHidden = true
    }

    hostingController.view.frame = bounds
    hostingController.view.setNeedsLayout()
    hostingController.view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    hostingController.view.layoutIfNeeded()

    let format = UIGraphicsImageRendererFormat()
    format.scale = configuration.scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(
      bounds: bounds,
      format: format
    )
    let image = renderer.image { context in
      hostingController.view.layer.render(in: context.cgContext)
    }

    try FileManager.default.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true
    )
    let data = try XCTUnwrap(image.pngData())
    try data.write(
      to: outputDirectory.appendingPathComponent(filename),
      options: .atomic
    )
    return image
  }
}
