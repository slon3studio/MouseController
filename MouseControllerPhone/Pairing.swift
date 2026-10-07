import CryptoKit
import Foundation
import Network
import Security

// Keep in sync with MouseControllerMac/Pairing.swift: both sides must
// derive the same TLS pre-shared key from the code.
enum Pairing {

    static let codeLength = 8

    static func normalized(_ input: String) -> String {
        input.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    static func formatted(_ code: String) -> String {
        let code = normalized(code)
        guard code.count > 4 else { return code }
        return "\(code.prefix(4))-\(code.dropFirst(4))"
    }

    // TLS with a pre-shared key derived from the pairing code: the handshake
    // only succeeds when both sides know the code, and everything sent after
    // it (including typed text) is encrypted.
    static func parameters(code: String) -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        // Nagle's algorithm would batch our tiny messages and add latency.
        tcpOptions.noDelay = true
        // Keepalive notices a peer that vanished without closing the socket
        // (Wi-Fi drop, Mac asleep) within a few seconds.
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2
        tcpOptions.keepaliveInterval = 1
        tcpOptions.keepaliveCount = 3

        let tlsOptions = NWProtocolTLS.Options()
        let securityOptions = tlsOptions.securityProtocolOptions

        let codeKey = SymmetricKey(data: Data(normalized(code).utf8))
        let psk = Data(HMAC<SHA256>.authenticationCode(
            for: Data("MouseController pairing v1".utf8),
            using: codeKey
        ))

        let pskData = psk.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityData = Data("MouseController".utf8).withUnsafeBytes { DispatchData(bytes: $0) }

        sec_protocol_options_add_pre_shared_key(
            securityOptions,
            pskData as __DispatchData,
            identityData as __DispatchData
        )

        if let cipherSuite = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256)) {
            sec_protocol_options_append_tls_ciphersuite(securityOptions, cipherSuite)
        }

        // PSK cipher suites are TLS 1.2 only.
        sec_protocol_options_set_max_tls_protocol_version(securityOptions, .TLSv12)

        return NWParameters(tls: tlsOptions, tcp: tcpOptions)
    }
}

/// Pairing codes per Mac, kept in the Keychain rather than UserDefaults
/// since a code is enough to control that Mac.
enum PairingStore {

    private static let service = "com.slon3studio.MouseController.pairing"

    static func code(for macID: String) -> String? {
        var query = baseQuery(for: macID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }

        return String(data: data, encoding: .utf8)
    }

    static func save(_ code: String, for macID: String) {
        remove(for: macID)

        var item = baseQuery(for: macID)
        item[kSecValueData as String] = Data(code.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func remove(for macID: String) {
        SecItemDelete(baseQuery(for: macID) as CFDictionary)
    }

    private static func baseQuery(for macID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: macID
        ]
    }
}
