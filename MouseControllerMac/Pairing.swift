import CryptoKit
import Foundation
import Network

// Keep in sync with MouseControllerPhone/Pairing.swift: both sides must
// derive the same TLS pre-shared key from the code.
enum Pairing {

    static let codeLength = 8

    // No 0/O, 1/I/L, so the code survives being read off a screen.
    private static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    static func newCode() -> String {
        String((0..<codeLength).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }

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
        tcpOptions.noDelay = true

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

        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        parameters.allowLocalEndpointReuse = true
        return parameters
    }
}
