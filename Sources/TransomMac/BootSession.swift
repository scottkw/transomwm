import Darwin

/// This boot's session ID, saved in layout.json's session record so a launch after a reboot (where window IDs and pids
/// restart and may repeat) matches every saved window by hints instead of by identity (RESEARCH Pitfall 5).
nonisolated public enum BootSession {
    /// `kern.bootsessionuuid`; nil if it cannot be read.
    public static func current() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else { return nil }
        let uuid = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return uuid.isEmpty ? nil : uuid
    }

    /// True only when both are known and differ: an unknown one (an older file) keeps the same-login assumption.
    public static func changed(saved: String?, current: String?) -> Bool {
        guard let saved, let current else { return false }
        return saved != current
    }
}
