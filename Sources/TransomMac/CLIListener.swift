import CoreFoundation
import Foundation
import TransomEngine
import os

/// The app's end of the `transom` tool's channel (D-07, RESEARCH Pattern 7). The port runs on the main queue, so each
/// request is decided and answered synchronously, and also in `swift test`, whose main thread runs no CFRunLoop (Pitfall 12).
/// Any local process can send here: the message ID, the size cap and the gate are the check (T-08-15).
/// The port holds this object unretained, so it must live as long as the port: the app keeps it for its lifetime.
@MainActor final class CLIListener {
    private var port: CFMessagePort?
    private let gate: CommandGate
    private let now: () -> ContinuousClock.Instant
    private let decide: (Command) -> String
    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "cli")

    /// False when another running instance holds the name (T-08-16).
    var isListening: Bool { port != nil }

    init(name: String, gate: CommandGate, now: @escaping () -> ContinuousClock.Instant = { .now }, decide: @escaping (Command) -> String) {
        self.gate = gate
        self.now = now
        self.decide = decide
        var context = CFMessagePortContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: CFMessagePortCallBack = { _, msgid, data, info in
            // Runs on the main queue, as set below. The system releases the returned data (CFMessagePort.h).
            let reply = MainActor.assumeIsolated {
                guard msgid == CLIProtocol.version, let info, let data, CFDataGetLength(data) <= CLIProtocol.maxRequestBytes,
                    let text = String(data: data as Data, encoding: .utf8)
                else { return CLIProtocol.rejected }
                return Unmanaged<CLIListener>.fromOpaque(info).takeUnretainedValue().reply(to: text)
            }
            return Unmanaged.passRetained(Data(reply.utf8) as CFData)
        }
        guard let port = CFMessagePortCreateLocal(nil, name as CFString, callback, &context, nil) else {
            logger.error("cli listener failed: couldn't register \(name, privacy: .public)")
            return
        }
        CFMessagePortSetDispatchQueue(port, .main)
        self.port = port
        logger.info("cli listener started on \(name, privacy: .public)")
    }

    private func reply(to text: String) -> String {
        guard let url = URL(string: text) else {
            logger.notice("cli rejected")
            return CLIProtocol.rejected
        }
        switch gate.admit(url, at: now()) {
        case .rejected:
            logger.notice("cli rejected")
            return CLIProtocol.rejected
        case .rateLimited:
            logger.info("cli rate limited")
            return CLIProtocol.rate
        case .command(let command):
            let reply = decide(command)
            logger.info("cli \(String(describing: command), privacy: .public): \(reply.replacingOccurrences(of: "\t", with: ": "), privacy: .public)")
            return reply
        }
    }
}
