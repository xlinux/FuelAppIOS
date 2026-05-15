//
//  DeviceIdProvider.swift
//  Fuel
//
//  Created by Danilo Benda on 15/05/26.
//


import Foundation
import Security

final class DeviceIdProvider {
    static let shared = DeviceIdProvider()

    private let service = "FuelApp"
    private let account = "deviceId"

    private init() {}

    func getDeviceId() -> String {
        if let existing = readFromKeychain() {
            return existing
        }

        let newId = UUID().uuidString
        saveToKeychain(newId)
        return newId
    }

    private func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func saveToKeychain(_ value: String) {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemAdd(attributes as CFDictionary, nil)
    }
}
