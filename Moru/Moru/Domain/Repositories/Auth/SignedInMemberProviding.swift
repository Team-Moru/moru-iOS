//
//  SignedInMemberProviding.swift
//  Moru
//

import Foundation

@MainActor
protocol SignedInMemberProviding: AnyObject {
  var signedInMemberID: Int64? { get }
}
