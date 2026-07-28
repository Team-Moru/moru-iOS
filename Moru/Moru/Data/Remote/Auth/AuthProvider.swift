//
//  AuthProvider.swift
//  Moru
//

import Foundation

nonisolated enum AuthProvider: Codable, Equatable, Hashable, Sendable {
  case apple
  case google
  case kakao
  case unknown(String)

  init(serverValue: String) {
    switch serverValue.lowercased() {
    case "apple":
      self = .apple
    case "google":
      self = .google
    case "kakao":
      self = .kakao
    default:
      self = .unknown(serverValue)
    }
  }

  var serverValue: String {
    switch self {
    case .apple:
      "apple"
    case .google:
      "google"
    case .kakao:
      "kakao"
    case .unknown(let value):
      value
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(serverValue: try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(serverValue)
  }
}
