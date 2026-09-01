//
//  RoutineSyncWireTarget.swift
//  Moru
//

import Alamofire
import Foundation
import Moya

/// Sends only a previously persisted wire artifact. It never owns DTO
/// encoding, account credentials, or retry-key generation.
nonisolated struct RoutineSyncWireTarget: MoruTargetType {
  let wireRequest: RoutineSyncWireRequest
  let idempotencyKey: UUID

  var path: String { wireRequest.path }

  var method: Moya.Method {
    switch wireRequest.method {
    case .post: .post
    case .delete: .delete
    case .patch: .patch
    }
  }

  var task: Moya.Task {
    switch wireRequest.method {
    case .post, .patch:
      .requestData(wireRequest.body)
    case .delete:
      .requestPlain
    }
  }

  var headers: [String: String]? {
    var headers = [
      "Accept": "application/json",
      "Idempotency-Key": idempotencyKey.uuidString,
    ]
    if wireRequest.method == .post || wireRequest.method == .patch {
      headers["Content-Type"] = "application/json"
    }
    return headers
  }

  var authenticationRequirement: AuthenticationRequirement { .bearer }
}
