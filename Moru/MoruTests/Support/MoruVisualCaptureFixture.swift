//
//  MoruVisualCaptureFixture.swift
//  MoruTests
//
//  Created by Codex on 7/24/26.
//

import Foundation
import QuartzCore
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
    stabilizeLayout(of: hostingController.view)

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

  private static func stabilizeLayout(
    of view: UIView,
    maximumPasses: Int = 8,
    requiredStablePasses: Int = 2
  ) {
    var previousState: LayoutState?
    var stablePasses = 0

    for _ in 0..<maximumPasses {
      view.setNeedsUpdateConstraints()
      view.updateConstraintsIfNeeded()
      view.setNeedsLayout()
      view.layoutIfNeeded()
      CATransaction.flush()
      _ = RunLoop.main.run(mode: .default, before: Date())
      view.layoutIfNeeded()
      CATransaction.flush()

      let currentState = LayoutState(rootView: view)
      if currentState == previousState {
        stablePasses += 1
        if stablePasses >= requiredStablePasses {
          return
        }
      } else {
        previousState = currentState
        stablePasses = 0
      }
    }
  }
}

private struct LayoutState: Equatable {
  let viewFrames: [CGRect]
  let viewBounds: [CGRect]
  let viewChildCounts: [Int]
  let layerFrames: [CGRect]
  let layerBounds: [CGRect]
  let layerPositions: [CGPoint]
  let layerOpacities: [Float]
  let layerChildCounts: [Int]

  init(rootView: UIView) {
    var viewFrames: [CGRect] = []
    var viewBounds: [CGRect] = []
    var viewChildCounts: [Int] = []
    var layerFrames: [CGRect] = []
    var layerBounds: [CGRect] = []
    var layerPositions: [CGPoint] = []
    var layerOpacities: [Float] = []
    var layerChildCounts: [Int] = []

    func appendViewState(_ view: UIView) {
      viewFrames.append(view.frame)
      viewBounds.append(view.bounds)
      viewChildCounts.append(view.subviews.count)
      view.subviews.forEach(appendViewState)
    }

    func appendLayerState(_ layer: CALayer) {
      layerFrames.append(layer.frame)
      layerBounds.append(layer.bounds)
      layerPositions.append(layer.position)
      layerOpacities.append(layer.opacity)
      layerChildCounts.append(layer.sublayers?.count ?? 0)
      layer.sublayers?.forEach(appendLayerState)
    }

    appendViewState(rootView)
    appendLayerState(rootView.layer)

    self.viewFrames = viewFrames
    self.viewBounds = viewBounds
    self.viewChildCounts = viewChildCounts
    self.layerFrames = layerFrames
    self.layerBounds = layerBounds
    self.layerPositions = layerPositions
    self.layerOpacities = layerOpacities
    self.layerChildCounts = layerChildCounts
  }
}
