//
//  APIResponse.swift
//  Moru
//

import Foundation

nonisolated struct APIResponse<Payload: Decodable & Sendable>: Decodable, Sendable {
  let isSuccess: Bool
  let code: String
  let message: String
  let result: Payload?
}

nonisolated extension APIResponse: Equatable where Payload: Equatable {}

nonisolated struct EmptyAPIResult: Decodable, Equatable, Sendable {}

nonisolated struct ServerErrorResponse: Decodable, Equatable, Sendable {
  let isSuccess: Bool?
  let code: String?
  let message: String?
}
