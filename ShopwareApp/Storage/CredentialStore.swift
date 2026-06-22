//
//  CredentialStore.swift
//  ShopwareApp
//
//  Keychain-backed storage for saved Shopware connections. Supports multiple
//  shops — each is stored as its own generic-password item keyed by the
//  connection's id. A non-secret pointer to the active shop lives in
//  UserDefaults. Connections saved by older single-shop builds are migrated
//  transparently on first load.
//

import Foundation
import Security

final class CredentialStore {
    private let service = "com.opensource.shopwareapp.connection"
    /// Account used by the original single-shop build, migrated on first load.
    private let legacyAccount = "shopware-admin-api"
    private let activeShopKey = "activeShopID"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Reads

    /// Every saved shop, oldest-first by id for a stable on-screen order.
    func loadAll() throws -> [ShopwareConnection] {
        try migrateLegacyIfNeeded()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        // "Nothing saved yet" and a few non-fatal read failures should surface
        // as an empty list, not a scary error on the first screen. Notably the
        // iOS Simulator can return errSecMissingEntitlement (-34018) when no
        // keychain item exists; treat that like "no shops".
        let emptyStatuses: [OSStatus] = [errSecItemNotFound, errSecMissingEntitlement]
        if emptyStatuses.contains(status) { return [] }

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw ShopwareAPIError.message("Could not read saved shops from Keychain.")
        }

        let connections = items.compactMap { item -> ShopwareConnection? in
            guard let data = item[kSecValueData as String] as? Data else { return nil }
            return try? JSONDecoder().decode(ShopwareConnection.self, from: data)
        }
        return connections.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    // MARK: - Writes

    /// Insert or update a shop, identified by its id.
    func save(_ connection: ShopwareConnection) throws {
        let data = try JSONEncoder().encode(connection)
        try delete(id: connection.id)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connection.id.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw ShopwareAPIError.message("Could not save the shop to Keychain.")
        }
    }

    /// Remove a single shop.
    func delete(id: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        try deleteMatching(query)
        if activeShopID == id { activeShopID = nil }
    }

    /// Remove every saved shop (used by "sign out of all shops").
    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        try deleteMatching(query)
        // Also clear any leftover legacy item.
        try deleteMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyAccount
        ])
        activeShopID = nil
    }

    // MARK: - Active shop pointer (non-secret)

    var activeShopID: UUID? {
        get {
            guard let raw = defaults.string(forKey: activeShopKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: activeShopKey)
            } else {
                defaults.removeObject(forKey: activeShopKey)
            }
        }
    }

    // MARK: - Helpers

    private func deleteMatching(_ query: [String: Any]) throws {
        let status = SecItemDelete(query as CFDictionary)
        let acceptable: [OSStatus] = [errSecSuccess, errSecItemNotFound, -25308]
        guard acceptable.contains(status) else {
            throw ShopwareAPIError.message("Could not update saved shops in Keychain.")
        }
    }

    /// Move a connection saved by the original single-shop build into the
    /// per-id format, then remove the legacy item. Runs at most once.
    private func migrateLegacyIfNeeded() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return }

        if let legacy = try? JSONDecoder().decode(ShopwareConnection.self, from: data) {
            // The decoded connection already has a synthesized id; persist it
            // under the new scheme and make it the active shop.
            try save(legacy)
            if activeShopID == nil { activeShopID = legacy.id }
        }
        try deleteMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyAccount
        ])
    }
}
