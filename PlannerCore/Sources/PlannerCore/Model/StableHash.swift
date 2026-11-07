import Foundation

/// Process-independent hashing (Swift's `Hasher` is randomly seeded per launch, so it can't be
/// used for identifiers or anything persisted).
public enum StableHash {
    /// 64-bit FNV-1a.
    public static func fnv1a64(_ bytes: some Sequence<UInt8>, seed: UInt64 = 0xcbf29ce484222325) -> UInt64 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    public static func fnv1a64(_ string: String) -> UInt64 { fnv1a64(Array(string.utf8)) }

    /// 8 hex chars — short content fingerprint for notification ids.
    public static func short(_ string: String) -> String {
        String(format: "%08x", UInt32(truncatingIfNeeded: fnv1a64(string)))
    }

    /// Deterministic RFC 4122-shaped UUID (version 5-style bits) from a name.
    public static func uuid(_ name: String) -> UUID {
        let a = fnv1a64(Array(name.utf8))
        let b = fnv1a64(Array(name.utf8), seed: 0x84222325cbf29ce4)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8(truncatingIfNeeded: a >> (UInt64(i) * 8)) }
        for i in 0..<8 { bytes[8 + i] = UInt8(truncatingIfNeeded: b >> (UInt64(i) * 8)) }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
