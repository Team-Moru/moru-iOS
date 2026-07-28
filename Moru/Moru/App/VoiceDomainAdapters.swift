//
//  VoiceDomainAdapters.swift
//  Moru
//

extension AccountSessionStore: SignedInMemberProviding {
  var signedInMemberID: Int64? {
    guard case .signedIn(let account) = state else {
      return nil
    }

    return account.memberID
  }
}
