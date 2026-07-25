//
//  KeychainCredentialStore.swift
//  Moru
//

import Foundation
import Security

nonisolated final class KeychainCredentialStore: CredentialStore {
  static let defaultAccount = "account-credentials-v1"

  let service: String
  let account: String

  init(
    service: String = Bundle.main.bundleIdentifier ?? "com.teammoru.Moru",
    account: String = KeychainCredentialStore.defaultAccount
  ) {
    self.service = service
    self.account = account
  }

  func load() throws -> AccountCredentials? {
    var result: CFTypeRef?
    let status = SecItemCopyMatching(
      Self.readQuery(service: service, account: account) as CFDictionary,
      &result
    )

    guard status != errSecItemNotFound else {
      return nil
    }
    guard status == errSecSuccess else {
      throw CredentialStoreError.keychain(status: status)
    }
    guard let data = result as? Data,
          !data.isEmpty else {
      throw CredentialStoreError.invalidStoredData
    }

    let credentials: AccountCredentials

    do {
      credentials = try JSONDecoder().decode(AccountCredentials.self, from: data)
    } catch {
      throw CredentialStoreError.invalidStoredData
    }

    guard credentials.isValid else {
      throw CredentialStoreError.invalidCredentials
    }

    return credentials
  }

  func save(_ credentials: AccountCredentials) throws {
    guard credentials.isValid else {
      throw CredentialStoreError.invalidCredentials
    }

    let data = try JSONEncoder().encode(credentials)
    let updateStatus = SecItemUpdate(
      Self.itemQuery(service: service, account: account) as CFDictionary,
      Self.updateAttributes(data: data) as CFDictionary
    )

    if updateStatus == errSecSuccess {
      return
    }

    guard updateStatus == errSecItemNotFound else {
      throw CredentialStoreError.keychain(status: updateStatus)
    }

    let addStatus = SecItemAdd(
      Self.addAttributes(
        service: service,
        account: account,
        data: data
      ) as CFDictionary,
      nil
    )

    guard addStatus == errSecSuccess else {
      throw CredentialStoreError.keychain(status: addStatus)
    }
  }

  func remove() throws {
    let status = SecItemDelete(
      Self.itemQuery(service: service, account: account) as CFDictionary
    )

    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CredentialStoreError.keychain(status: status)
    }
  }

  static func itemQuery(
    service: String,
    account: String
  ) -> [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecAttrSynchronizable: kCFBooleanFalse as Any,
    ]
  }

  static func readQuery(
    service: String,
    account: String
  ) -> [CFString: Any] {
    itemQuery(service: service, account: account).merging(
      [
        kSecReturnData: kCFBooleanTrue as Any,
        kSecMatchLimit: kSecMatchLimitOne,
      ],
      uniquingKeysWith: { _, new in new }
    )
  }

  static func updateAttributes(data: Data) -> [CFString: Any] {
    [
      kSecValueData: data,
      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
  }

  static func addAttributes(
    service: String,
    account: String,
    data: Data
  ) -> [CFString: Any] {
    itemQuery(service: service, account: account).merging(
      updateAttributes(data: data),
      uniquingKeysWith: { _, new in new }
    )
  }
}
