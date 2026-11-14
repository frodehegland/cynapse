// Signature.swift — a bank is only run if it is signed by the key it claims.
//
// Ed25519, as raw 32-byte keys in base64. The signature is over the bank
// file's exact bytes, so a bank cannot be changed by even one character
// without it showing.

import Foundation
import Crypto

enum Signature {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum BankSignature {

    public enum Failure: Error, CustomStringConvertible {
        case unreadableKey
        case unreadableSignature
        case mismatch

        public var description: String {
            switch self {
            case .unreadableKey: "The public key could not be read."
            case .unreadableSignature: "The signature file could not be read."
            case .mismatch: "This question bank's signature does not match. It may have been changed, so it will not be used."
            }
        }
    }

    /// Checks `signature` (base64) over `data` with `publicKey` (base64).
    public static func verify(_ data: Data, signature: String, publicKey: String) throws {
        guard let keyData = Data(base64Encoded: publicKey.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { throw Failure.unreadableKey }
        guard let signatureData = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw Failure.unreadableSignature
        }
        guard key.isValidSignature(signatureData, for: data) else { throw Failure.mismatch }
    }

    /// A new key pair, both base64.
    public static func makeKeyPair() -> (privateKey: String, publicKey: String) {
        let key = Curve25519.Signing.PrivateKey()
        return (key.rawRepresentation.base64EncodedString(), key.publicKey.rawRepresentation.base64EncodedString())
    }

    /// The signature of `data` with `privateKey` (base64), as base64.
    public static func sign(_ data: Data, privateKey: String) throws -> String {
        guard let keyData = Data(base64Encoded: privateKey.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else { throw Failure.unreadableKey }
        return try key.signature(for: data).base64EncodedString()
    }

    /// Reads and verifies a bank: `url` and `url` + ".sig".
    public static func loadVerified(_ url: URL, publicKey: String) throws -> Bank {
        let data = try Data(contentsOf: url)
        let signature = try String(contentsOf: url.appendingPathExtension("sig"), encoding: .utf8)
        try verify(data, signature: signature, publicKey: publicKey)
        return try JSONDecoder().decode(Bank.self, from: data)
    }
}
