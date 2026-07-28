//
//  AccountSessionStore+RoutineSuggestionAccountProviding.swift
//  Moru
//

extension AccountSessionStore: RoutineSuggestionAccountProviding {
  var routineSuggestionMemberID: Int64? {
    guard case .signedIn(let account) = state else {
      return nil
    }

    return account.memberID
  }
}
