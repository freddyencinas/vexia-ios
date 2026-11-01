import Foundation
import CryptoKit

/// PIN hashing: hex(SHA256(pin + salt)),
/// salt = 16 random bytes base64url.
nonisolated enum PINHasher {
    static func makeSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }
    static func hash(pin: String, salt: String) -> String {
        SHA256.hash(data: Data((pin + salt).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func isValid(_ pin: String) -> Bool { pin.count >= 4 && pin.count <= 6 && pin.allSatisfy(\.isNumber) }
}
