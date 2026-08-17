//
//  AccountSessionStore+SignedInMemberProviding.swift
//  Moru
//

extension AccountSessionStore:
  SignedInMemberProviding,
  CurrentAccountSessionIdentityProviding {
  var signedInMemberID: Int64? {
    guard case .signedIn(let account) = state else {
      return nil
    }

    return account.memberID
  }

  var currentAccountSessionIdentity: AccountSessionIdentity? {
    guard case .signedIn = state else {
      return nil
    }
    return currentAuthorizationContext().map {
      AccountSessionIdentity(memberID: $0.memberID, sessionID: $0.sessionID)
    }
  }
}
