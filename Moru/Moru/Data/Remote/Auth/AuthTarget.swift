//
//  AuthTarget.swift
//  Moru
//

import Foundation

import Alamofire
import Moya

nonisolated enum AuthTarget: MoruTargetType {
  case login(provider: AuthProvider, request: SocialLoginRequestDTO)
  case reissue(refreshToken: String)
  case logout(request: LogoutRequestDTO)
  case withdrawal

  var path: String {
    switch self {
    case .login(let provider, _):
      "/auth/login/\(provider.serverValue)"
    case .reissue:
      "/auth/reissue"
    case .logout:
      "/auth/logout"
    case .withdrawal:
      "/auth/withdrawal"
    }
  }

  var method: Moya.Method {
    switch self {
    case .login,
         .reissue,
         .logout:
      .post
    case .withdrawal:
      .delete
    }
  }

  var task: Moya.Task {
    switch self {
    case .login(_, let request):
      .requestJSONEncodable(request)
    case .reissue,
         .withdrawal:
      .requestPlain
    case .logout(let request):
      .requestJSONEncodable(request)
    }
  }

  var headers: [String: String]? {
    var values = ["Accept": "application/json"]

    if case .reissue(let refreshToken) = self {
      values["X-Refresh-Token"] = refreshToken
    }

    return values
  }

  var authenticationRequirement: AuthenticationRequirement {
    switch self {
    case .login,
         .reissue:
      .none
    case .logout,
         .withdrawal:
      .bearer
    }
  }

  var sampleData: Data {
    switch self {
    case .login:
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "memberId": 1,
            "accessToken": "sample-access-token",
            "refreshToken": "sample-refresh-token",
            "isNewMember": true,
            "onboardingCompleted": false
          }
        }
        """.utf8
      )
    case .reissue:
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "accessToken": "sample-access-token",
            "refreshToken": "sample-refresh-token",
            "tokenType": "Bearer",
            "memberId": 1,
            "onboardingCompleted": false
          }
        }
        """.utf8
      )
    case .logout:
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다."
        }
        """.utf8
      )
    case .withdrawal:
      Data(
        """
        {
          "isSuccess": true,
          "code": "COMMON200",
          "message": "성공입니다.",
          "result": {
            "message": "회원 탈퇴가 완료되었습니다."
          }
        }
        """.utf8
      )
    }
  }
}

extension AuthTarget: AuthenticationRetryTargetProviding {
  func targetForAuthenticationRetry(
    using result: AccessTokenRefreshResult
  ) -> any MoruTargetType {
    switch self {
    case .logout:
      AuthTarget.logout(
        request: LogoutRequestDTO(refreshToken: result.refreshToken)
      )
    case .login, .reissue, .withdrawal:
      self
    }
  }
}
