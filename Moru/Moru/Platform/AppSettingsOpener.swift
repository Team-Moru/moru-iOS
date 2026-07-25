//
//  AppSettingsOpener.swift
//  Moru
//

import Foundation
import UIKit

@MainActor
struct AppSettingsOpener {
  typealias OpenURL = @MainActor (URL) async -> Bool

  private let openURL: OpenURL

  init(
    openURL: @escaping OpenURL = { url in
      await UIApplication.shared.open(url)
    }
  ) {
    self.openURL = openURL
  }

  @discardableResult
  func open() async -> Bool {
    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
      return false
    }

    return await openURL(settingsURL)
  }
}
