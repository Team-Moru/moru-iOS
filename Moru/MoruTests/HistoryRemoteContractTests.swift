//
//  HistoryRemoteContractTests.swift
//  MoruTests
//

import Foundation
import XCTest

import Moya

@testable import Moru

@MainActor
final class HistoryRemoteContractTests: XCTestCase {
  func testTargetsMatchOpenAPIAndSamplesDecode() throws {
    let weekly = HistoryTarget.weekly
    let monthly = HistoryTarget.monthly(year: 2026, month: 4)

    XCTAssertEqual(weekly.path, "/routine-executions/weekly")
    XCTAssertEqual(monthly.path, "/routine-executions/monthly")
    XCTAssertEqual(weekly.method, .get)
    XCTAssertEqual(monthly.method, .get)
    XCTAssertEqual(weekly.authenticationRequirement, .bearer)
    XCTAssertEqual(monthly.authenticationRequirement, .bearer)

    guard case .requestParameters(let parameters, _) = monthly.task else {
      return XCTFail("Expected the monthly query parameters.")
    }
    XCTAssertEqual(parameters["year"] as? Int, 2026)
    XCTAssertEqual(parameters["month"] as? Int, 4)

    let decoder = JSONDecoder()
    let weeklyEnvelope = try decoder.decode(
      APIResponse<HistoryWeeklyResponseDTO>.self,
      from: weekly.sampleData
    )
    let monthlyEnvelope = try decoder.decode(
      APIResponse<[HistoryMonthlyDayDTO]>.self,
      from: monthly.sampleData
    )
    XCTAssertEqual(weeklyEnvelope.result?.weeklyCompletionRate.count, 7)
    XCTAssertNil(
      weeklyEnvelope.result?.weeklyCompletionRate[4].completionRate
    )
    XCTAssertEqual(
      monthlyEnvelope.result?.first?.executedDate,
      "2026-04-01"
    )
  }

  func testFetchesAccountHistoryEndpointsAndMapsValidatedSummary()
    async throws {
    let capture = HistoryRequestCapturePlugin()
    let service = makeService(additionalPlugins: [capture])

    let summary = try await service.fetchSummary(
      year: 2026,
      month: 4,
      memberID: 98
    )

    XCTAssertEqual(summary.weekly.completionRate, 0.75)
    XCTAssertEqual(
      summary.weekly.completionRateChangePercentagePoints,
      -10
    )
    XCTAssertEqual(summary.weekly.totalDurationSeconds, 3_600)
    XCTAssertEqual(
      summary.weekly.dailyCompletions.map(\.weekday),
      ServerHistoryWeekday.allCases
    )
    XCTAssertEqual(
      summary.weekly.dailyCompletions.map(\.completionRate),
      [1, 0.8, 0.6, 0.6, nil, nil, nil]
    )
    XCTAssertEqual(summary.weekly.routineStats.first?.routineID, 1)
    XCTAssertEqual(summary.weekly.routineStats.first?.title, "물 마시기")
    XCTAssertEqual(
      summary.weekly.routineStats.first?.completionRate,
      0.6
    )
    XCTAssertEqual(
      summary.monthlyDays,
      [
        ServerHistoryMonthlyDay(
          year: 2026,
          month: 4,
          day: 1,
          completionRate: 0.8
        ),
        ServerHistoryMonthlyDay(
          year: 2026,
          month: 4,
          day: 3,
          completionRate: 1
        ),
      ]
    )
    let requests = capture.requests
    XCTAssertEqual(requests.count, 2)
    XCTAssertEqual(
      Set(requests.compactMap(\.url?.path)),
      Set([
        "/routine-executions/weekly",
        "/routine-executions/monthly",
      ])
    )
    XCTAssertTrue(
      requests.allSatisfy {
        $0.httpMethod == "GET"
          && $0.value(forHTTPHeaderField: "Authorization")
            == "Bearer access-token"
          && $0.httpBody == nil
      }
    )

    let monthlyRequest = try XCTUnwrap(
      requests.first {
        $0.url?.path == "/routine-executions/monthly"
      }
    )
    let queryItems = URLComponents(
      url: try XCTUnwrap(monthlyRequest.url),
      resolvingAgainstBaseURL: false
    )?.queryItems ?? []
    XCTAssertEqual(
      Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) }),
      ["year": "2026", "month": "4"]
    )
  }

  func testFetchStartsWeeklyAndMonthlyConcurrently() async throws {
    let gate = HistoryRequestGate(expectedRequestCount: 2)
    let service = DefaultAccountHistoryRemoteService(
      apiClient: ConcurrentHistoryAPIClient(gate: gate)
    )
    let task = _Concurrency.Task {
      try await service.fetchSummary(
        year: 2026,
        month: 4,
        memberID: 98
      )
    }

    await gate.waitUntilAllRequestsArrive()
    let targets = await gate.requestedTargets

    XCTAssertEqual(
      Set(targets),
      Set([
        "/routine-executions/weekly",
        "/routine-executions/monthly",
      ])
    )

    await gate.releaseRequests()
    _ = try await task.value
  }

  func testRejectsInvalidMemberYearAndMonthBeforeTransport() async {
    let client = HistoryCallCountingAPIClient()
    let service = DefaultAccountHistoryRemoteService(apiClient: client)
    let invalidRequests = [
      (2026, 4, Int64(0)),
      (1999, 4, Int64(98)),
      (10_000, 4, Int64(98)),
      (2026, 0, Int64(98)),
      (2026, 13, Int64(98)),
    ]

    for (year, month, memberID) in invalidRequests {
      await assertRemoteError(.invalidRequest) {
        _ = try await service.fetchSummary(
          year: year,
          month: month,
          memberID: memberID
        )
      }
    }

    XCTAssertEqual(client.callCount, 0)
  }

  func testRejectsMalformedWeeklyCoverageAndRates() async {
    let invalidWeeklyResponses = [
      Self.weeklyData(
        days: """
        {"day": "MON", "completionRate": 100},
        {"day": "MON", "completionRate": 80},
        {"day": "WED", "completionRate": 60},
        {"day": "THU", "completionRate": 60},
        {"day": "FRI", "completionRate": null},
        {"day": "SAT", "completionRate": null},
        {"day": "SUN", "completionRate": null}
        """
      ),
      Self.weeklyData(
        days: """
        {"day": "MON", "completionRate": 101},
        {"day": "TUE", "completionRate": 80},
        {"day": "WED", "completionRate": 60},
        {"day": "THU", "completionRate": 60},
        {"day": "FRI", "completionRate": null},
        {"day": "SAT", "completionRate": null},
        {"day": "SUN", "completionRate": null}
        """
      ),
      Self.weeklyData(completionRate: -1),
      Self.weeklyData(completionRateDiff: 101),
      Self.weeklyData(totalDurationSecond: -1),
      Self.weeklyData(
        routineStats: """
        [
          {"routineId": 0, "title": "물 마시기", "completionRate": 60}
        ]
        """
      ),
    ]

    for weekly in invalidWeeklyResponses {
      await assertRemoteError(.invalidResponse) {
        _ = try await makeService(weeklyData: weekly).fetchSummary(
          year: 2026,
          month: 4,
          memberID: 98
        )
      }
    }
  }

  func testRejectsMalformedWrongMonthDuplicateAndOutOfRangeMonthlyDays()
    async {
    let invalidMonthlyResponses = [
      Self.monthlyData(entries: [
        ("2026-4-01", 80),
      ]),
      Self.monthlyData(entries: [
        ("2026-05-01", 80),
      ]),
      Self.monthlyData(entries: [
        ("2026-04-31", 80),
      ]),
      Self.monthlyData(entries: [
        ("2026-04-01", 80),
        ("2026-04-01", 100),
      ]),
      Self.monthlyData(entries: [
        ("2026-04-01", -1),
      ]),
    ]

    for monthly in invalidMonthlyResponses {
      await assertRemoteError(.invalidResponse) {
        _ = try await makeService(monthlyData: monthly).fetchSummary(
          year: 2026,
          month: 4,
          memberID: 98
        )
      }
    }
  }

  func testMapsAccountAuthorizationChangeAndPreservesCancellation()
    async {
    let accountService = DefaultAccountHistoryRemoteService(
      apiClient: HistoryThrowingAPIClient(
        error: AccountAuthorizationContextError.memberMismatch
      )
    )
    await assertRemoteError(.accountAuthorizationChanged) {
      _ = try await accountService.fetchSummary(
        year: 2026,
        month: 4,
        memberID: 98
      )
    }

    for error in [CancellationError(), APIError.cancelled] as [any Error] {
      let cancellationService = DefaultAccountHistoryRemoteService(
        apiClient: HistoryThrowingAPIClient(error: error)
      )

      do {
        _ = try await cancellationService.fetchSummary(
          year: 2026,
          month: 4,
          memberID: 98
        )
        XCTFail("Expected cancellation.")
      } catch is CancellationError {
        continue
      } catch {
        XCTFail("Expected CancellationError, got \(error)")
      }
    }
  }

  private func assertRemoteError(
    _ expected: AccountHistoryRemoteError,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected).")
    } catch let error as AccountHistoryRemoteError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Expected AccountHistoryRemoteError, got \(error)")
    }
  }

  nonisolated private func makeService(
    weeklyData: Data? = nil,
    monthlyData: Data? = nil,
    additionalPlugins: [any PluginType & Sendable] = []
  ) -> DefaultAccountHistoryRemoteService {
    let responses = [
      "/routine-executions/weekly": weeklyData ?? Self.weeklyData(),
      "/routine-executions/monthly": monthlyData ?? Self.monthlyData(),
    ]
    let client = DefaultAPIClient(
      tokenProvider: HistoryAccessTokenProvider(),
      providerFactory: MoyaProviderFactory(
        endpointBuilder: { target in
          let endpoint = MoyaProvider<MultiTarget>.defaultEndpointMapping(
            for: target
          )
          return Endpoint(
            url: endpoint.url,
            sampleResponseClosure: {
              .networkResponse(
                200,
                responses[target.path] ?? Data()
              )
            },
            method: endpoint.method,
            task: endpoint.task,
            httpHeaderFields: endpoint.httpHeaderFields
          )
        },
        stubBuilder: { _ in .immediate },
        additionalPlugins: additionalPlugins
      )
    )

    return DefaultAccountHistoryRemoteService(apiClient: client)
  }

  nonisolated private static func weeklyData(
    completionRate: Int = 75,
    completionRateDiff: Int = -10,
    totalDurationSecond: Int = 3_600,
    days: String = """
      {"day": "MON", "completionRate": 100},
      {"day": "TUE", "completionRate": 80},
      {"day": "WED", "completionRate": 60},
      {"day": "THU", "completionRate": 60},
      {"day": "FRI", "completionRate": null},
      {"day": "SAT", "completionRate": null},
      {"day": "SUN", "completionRate": null}
      """,
    routineStats: String = """
      [
        {"routineId": 1, "title": " 물 마시기 ", "completionRate": 60}
      ]
      """
  ) -> Data {
    Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": {
          "completionRate": \(completionRate),
          "completionRateDiff": \(completionRateDiff),
          "totalDurationSecond": \(totalDurationSecond),
          "weeklyCompletionRate": [\(days)],
          "routineStats": \(routineStats)
        }
      }
      """.utf8
    )
  }

  nonisolated private static func monthlyData(
    entries: [(String, Int)] = [
      ("2026-04-03", 100),
      ("2026-04-01", 80),
    ]
  ) -> Data {
    let result = entries
      .map {
        """
        {"executedDate": "\($0.0)", "completionRate": \($0.1)}
        """
      }
      .joined(separator: ",")

    return Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": [\(result)]
      }
      """.utf8
    )
  }

}

nonisolated private final class HistoryAccessTokenProvider:
  AccountBoundAccessTokenProviding {
  private let context = AccountAuthorizationContext(
    memberID: 98,
    accessToken: "access-token",
    sessionID: UUID()
  )

  var accessToken: String? {
    context.accessToken
  }

  func authorizationContext(
    forMemberID memberID: Int64
  ) -> AccountAuthorizationContext? {
    context.memberID == memberID ? context : nil
  }
}

nonisolated private final class HistoryRequestCapturePlugin:
  PluginType,
  @unchecked Sendable {
  private let lock = NSLock()
  private var capturedRequests: [URLRequest] = []

  var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return capturedRequests
  }

  func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
    lock.lock()
    capturedRequests.append(request)
    lock.unlock()
    return request
  }
}

nonisolated private final class HistoryCallCountingAPIClient:
  AccountBoundAPIClient,
  @unchecked Sendable {
  private let lock = NSLock()
  private var requestCallCount = 0

  var callCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return requestCallCount
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  func requestVoid<Target: MoruTargetType>(_ target: Target) async throws {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  private func recordCall() {
    lock.lock()
    requestCallCount += 1
    lock.unlock()
  }
}

nonisolated private final class HistoryThrowingAPIClient:
  AccountBoundAPIClient,
  @unchecked Sendable {
  private let error: any Error

  init(error: any Error) {
    self.error = error
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    throw error
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    throw error
  }

  func requestVoid<Target: MoruTargetType>(_ target: Target) async throws {
    throw error
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    throw error
  }
}

nonisolated private final class ConcurrentHistoryAPIClient:
  AccountBoundAPIClient,
  Sendable {
  private let gate: HistoryRequestGate

  init(gate: HistoryRequestGate) {
    self.gate = gate
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    throw APIError.invalidRequest("Expected an account-bound request.")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    guard let target = target as? HistoryTarget else {
      throw APIError.invalidRequest("Unexpected target.")
    }

    await gate.arrive(path: target.path)

    let response: any Sendable
    switch target {
    case .weekly:
      response = HistoryWeeklyResponseDTO(
        completionRate: 75,
        completionRateDiff: -10,
        totalDurationSecond: 3_600,
        weeklyCompletionRate: zip(
          ServerHistoryWeekday.allCases,
          [100, 80, 60, 60, nil, nil, nil] as [Int?]
        ).map {
          HistoryWeekdayCompletionDTO(
            day: $0.0.rawValue,
            completionRate: $0.1
          )
        },
        routineStats: []
      )
    case .monthly:
      response = [
        HistoryMonthlyDayDTO(
          executedDate: "2026-04-01",
          completionRate: 80
        ),
      ]
    }

    guard let payload = response as? Payload else {
      throw APIError.decoding("Unexpected payload type.")
    }
    return payload
  }

  func requestVoid<Target: MoruTargetType>(_ target: Target) async throws {
    throw APIError.invalidRequest("Unexpected void request.")
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    throw APIError.invalidRequest("Unexpected data request.")
  }
}

private actor HistoryRequestGate {
  private let expectedRequestCount: Int
  private var waitingRequests: [CheckedContinuation<Void, Never>] = []
  private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var requestedTargets: [String] = []

  init(expectedRequestCount: Int) {
    self.expectedRequestCount = expectedRequestCount
  }

  func arrive(path: String) async {
    requestedTargets.append(path)

    if requestedTargets.count == expectedRequestCount {
      let waiters = arrivalWaiters
      arrivalWaiters.removeAll()
      waiters.forEach { $0.resume() }
    }

    await withCheckedContinuation { continuation in
      waitingRequests.append(continuation)
    }
  }

  func waitUntilAllRequestsArrive() async {
    guard requestedTargets.count < expectedRequestCount else {
      return
    }

    await withCheckedContinuation { continuation in
      arrivalWaiters.append(continuation)
    }
  }

  func releaseRequests() {
    let requests = waitingRequests
    waitingRequests.removeAll()
    requests.forEach { $0.resume() }
  }
}
