//
//  OnboardingStatusRemoteContractTests.swift
//  MoruTests
//

import Foundation
import XCTest

import Moya

@testable import Moru

@MainActor
final class OnboardingStatusRemoteContractTests: XCTestCase {
  func testTargetMatchesProductionContractAndSampleDecodes() throws {
    let target = OnboardingStatusTarget.status

    XCTAssertEqual(target.path, "/onboarding/status")
    XCTAssertEqual(target.method, .get)
    XCTAssertEqual(target.authenticationRequirement, .bearer)
    guard case .requestPlain = target.task else {
      return XCTFail("Expected a body-free GET request.")
    }

    let envelope = try JSONDecoder().decode(
      OnboardingStatusEnvelopeDTO.self,
      from: target.sampleData
    )
    XCTAssertTrue(envelope.isSuccess)
    XCTAssertTrue(try XCTUnwrap(envelope.result).onboardingCompleted)
  }

  func testFetchMapsTrueAndFalseResponses() async throws {
    for isCompleted in [true, false] {
      let identity = AccountSessionIdentity(
        memberID: 98,
        sessionID: UUID()
      )
      let client = OnboardingStatusAPIClientStub(
        behavior: .data(responseData(isCompleted: isCompleted))
      )
      let service = DefaultOnboardingStatusRemoteService(
        apiClient: client
      )

      let status = try await service.fetchStatus(for: identity)
      let captures = await client.captures()

      XCTAssertEqual(status.isCompleted, isCompleted)
      XCTAssertEqual(
        captures,
        [OnboardingStatusRequestCapture(path: "/onboarding/status", identity: identity)]
      )
    }
  }

  func testMissingNullAndMalformedResultAreInvalidResponse() async {
    let invalidResponses = [
      """
      {"isSuccess":true,"code":"COMMON200","message":"ok"}
      """,
      """
      {"isSuccess":true,"code":"COMMON200","message":"ok","result":null}
      """,
      """
      {"isSuccess":true,"code":"COMMON200","message":"ok","result":{}}
      """,
      """
      {
        "isSuccess":true,
        "code":"COMMON200",
        "message":"ok",
        "result":{"onboardingCompleted":null}
      }
      """,
      """
      {
        "isSuccess":true,
        "code":"COMMON200",
        "message":"ok",
        "result":{"onboardingCompleted":"true"}
      }
      """,
      "not-json",
    ]

    for response in invalidResponses {
      let service = DefaultOnboardingStatusRemoteService(
        apiClient: OnboardingStatusAPIClientStub(
          behavior: .data(Data(response.utf8))
        )
      )
      await assertRemoteError(.invalidResponse) {
        _ = try await service.fetchStatus(for: validIdentity())
      }
    }
  }

  func testSuccessfulHTTPErrorEnvelopeRemainsServerFailure() async {
    let service = DefaultOnboardingStatusRemoteService(
      apiClient: OnboardingStatusAPIClientStub(
        behavior: .data(
          Data(
            """
            {
              "isSuccess": false,
              "code": "ONBOARDING_ERROR",
              "message": "failed",
              "result": {"onboardingCompleted":"malformed"}
            }
            """.utf8
          )
        )
      )
    )

    do {
      _ = try await service.fetchStatus(for: validIdentity())
      XCTFail("Expected a server error.")
    } catch let error as APIError {
      XCTAssertEqual(
        error,
        .server(
          statusCode: 200,
          code: "ONBOARDING_ERROR",
          message: "failed"
        )
      )
    } catch {
      XCTFail("Expected APIError, got \(error)")
    }
  }

  func testRejectsInvalidMemberBeforeTransport() async {
    let client = OnboardingStatusAPIClientStub(
      behavior: .data(responseData(isCompleted: true))
    )
    let service = DefaultOnboardingStatusRemoteService(apiClient: client)

    await assertRemoteError(.invalidRequest) {
      _ = try await service.fetchStatus(
        for: AccountSessionIdentity(
          memberID: 0,
          sessionID: UUID()
        )
      )
    }

    let captures = await client.captures()
    XCTAssertEqual(captures, [])
  }

  func testPassesExactMemberAndSessionIdentityToAccountBoundClient()
    async throws {
    let firstSession = UUID()
    let secondSession = UUID()
    let identity = AccountSessionIdentity(
      memberID: 98,
      sessionID: secondSession
    )
    XCTAssertNotEqual(firstSession, secondSession)
    let client = OnboardingStatusAPIClientStub(
      behavior: .data(responseData(isCompleted: true))
    )
    let service = DefaultOnboardingStatusRemoteService(apiClient: client)

    _ = try await service.fetchStatus(for: identity)

    let captures = await client.captures()
    let memberOnlyRequestCount = await client.memberOnlyRequestCount()
    XCTAssertEqual(captures.map(\.identity), [identity])
    XCTAssertEqual(memberOnlyRequestCount, 0)
  }

  func testCancellationAndAuthorizationChangeRemainDistinct() async {
    for behavior in [
      OnboardingStatusAPIClientStub.Behavior.cancellationError,
      .apiCancelled,
    ] {
      let service = DefaultOnboardingStatusRemoteService(
        apiClient: OnboardingStatusAPIClientStub(behavior: behavior)
      )

      do {
        _ = try await service.fetchStatus(for: validIdentity())
        XCTFail("Expected cancellation.")
      } catch is CancellationError {
        continue
      } catch {
        XCTFail("Expected CancellationError, got \(error)")
      }
    }

    let changedAccountService = DefaultOnboardingStatusRemoteService(
      apiClient: OnboardingStatusAPIClientStub(
        behavior: .authorizationChanged
      )
    )
    await assertRemoteError(.accountAuthorizationChanged) {
      _ = try await changedAccountService.fetchStatus(
        for: validIdentity()
      )
    }
  }

  func testTransportTimeoutOfflineAndServerErrorsArePreserved() async {
    let errors = [
      APIError.transport(code: -1, message: "transport"),
      APIError.transport(
        code: URLError.timedOut.rawValue,
        message: "timeout"
      ),
      APIError.transport(
        code: URLError.notConnectedToInternet.rawValue,
        message: "offline"
      ),
      APIError.server(
        statusCode: 503,
        code: "COMMON503",
        message: "unavailable"
      ),
    ]

    for expected in errors {
      let service = DefaultOnboardingStatusRemoteService(
        apiClient: OnboardingStatusAPIClientStub(
          behavior: .apiError(expected)
        )
      )

      do {
        _ = try await service.fetchStatus(for: validIdentity())
        XCTFail("Expected \(expected).")
      } catch let error as APIError {
        XCTAssertEqual(error, expected)
      } catch {
        XCTFail("Expected APIError, got \(error)")
      }
    }
  }

  private func assertRemoteError(
    _ expected: OnboardingStatusRemoteError,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected).")
    } catch let error as OnboardingStatusRemoteError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Expected OnboardingStatusRemoteError, got \(error)")
    }
  }
}

nonisolated private func validIdentity() -> AccountSessionIdentity {
  AccountSessionIdentity(memberID: 98, sessionID: UUID())
}

nonisolated private func responseData(isCompleted: Bool) -> Data {
  Data(
    """
    {
      "isSuccess": true,
      "code": "COMMON200",
      "message": "ok",
      "result": {
        "onboardingCompleted": \(isCompleted)
      }
    }
    """.utf8
  )
}

nonisolated private struct OnboardingStatusRequestCapture:
  Equatable,
  Sendable {
  let path: String
  let identity: AccountSessionIdentity
}

private actor OnboardingStatusAPIClientStub: AccountBoundAPIClient {
  enum Behavior: Sendable {
    case data(Data)
    case cancellationError
    case apiCancelled
    case authorizationChanged
    case apiError(APIError)
  }

  private let behavior: Behavior
  private var requestCaptures: [OnboardingStatusRequestCapture] = []
  private var memberOnlyRequests = 0

  init(behavior: Behavior) {
    self.behavior = behavior
  }

  func captures() -> [OnboardingStatusRequestCapture] {
    requestCaptures
  }

  func memberOnlyRequestCount() -> Int {
    memberOnlyRequests
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> Data {
    requestCaptures.append(
      OnboardingStatusRequestCapture(
        path: target.path,
        identity: identity
      )
    )

    switch behavior {
    case .data(let data):
      return data
    case .cancellationError:
      throw CancellationError()
    case .apiCancelled:
      throw APIError.cancelled
    case .authorizationChanged:
      throw AccountAuthorizationContextError.memberMismatch
    case .apiError(let error):
      throw error
    }
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _: Target,
    as _: Payload.Type
  ) async throws -> Payload {
    throw APIError.invalidRequest("Unexpected unbound request.")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _: Target,
    as _: Payload.Type,
    authorizedForMemberID _: Int64
  ) async throws -> Payload {
    memberOnlyRequests += 1
    throw APIError.invalidRequest("Unexpected member-only request.")
  }

  func requestVoid<Target: MoruTargetType>(
    _: Target
  ) async throws {
    throw APIError.invalidRequest("Unexpected void request.")
  }

  func requestData<Target: MoruTargetType>(
    _: Target
  ) async throws -> Data {
    throw APIError.invalidRequest("Unexpected unbound request.")
  }
}
