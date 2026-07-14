//
//  RoutineLaunchContract.swift
//  Moru
//
//  Created by Codex on 7/14/26.
//

import Foundation

struct RoutineLaunchRequest: Equatable {
  let routineID: UUID
}

enum RoutineLaunchResult: Equatable {
  case started
  case alreadyRunning
  case busy

}

typealias RoutineLaunchHandler = @MainActor (RoutineLaunchRequest) -> RoutineLaunchResult
