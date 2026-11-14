// Keychain.swift — the person's own cloud keys, kept in their Keychain and
// nowhere else. Cynapse carries no keys of its own.

import Foundation
import Security
import ModelCheckModels

enum Keychain {

    private static func service(_ provider: CloudModel.Provider) -> String { "info.liquid.cynapse.\(provider.rawValue)" }

    static func key(for provider: CloudModel.Provider) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service(provider),
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setKey(_ key: String, for provider: CloudModel.Provider) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service(provider)]
        SecItemDelete(base as CFDictionary)
        guard !key.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
