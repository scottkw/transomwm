import Foundation
import ServiceManagement
import os

/// `SMAppService.Status`, in Transom's words (RESEARCH Pattern 7).
public enum LoginItemStatus: Equatable, Sendable {
    case enabled, notRegistered, requiresApproval, notFound
}

/// Launch at login (SHIP-03). A protocol so tests use a fake and never register the host's real login item.
public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

/// `SMAppService.mainApp`: the app's own signed bundle, nothing else.
public final class SystemLoginItem: LoginItemService {
    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "login")

    public init() {}

    public var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .notRegistered
        @unknown default: .notRegistered
        }
    }

    public func register() throws {
        defer { log() }
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        defer { log() }
        try SMAppService.mainApp.unregister()
    }

    public func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func log() {
        logger.info("login item \(String(describing: self.status), privacy: .public)")
    }
}

/// What the "Open Transom at login" row shows for a status (UI-SPEC Tab 1 Startup).
public struct LoginItemToggle: Equatable {
    public let status: LoginItemStatus
    public let lastError: String?

    public init(status: LoginItemStatus, lastError: String? = nil) {
        self.status = status
        self.lastError = lastError
    }

    /// `.requiresApproval` keeps the toggle on, with the approval row under it.
    public var isOn: Bool { status == .enabled || status == .requiresApproval }
    public var needsApproval: Bool { status == .requiresApproval }
    /// With approval pending, the approval row is the next step, so the error footer stays hidden.
    public var footer: String? { lastError == nil || needsApproval ? nil : SettingsCopy.loginItemFailed }

    /// Registers or unregisters, then re-reads the status. An error is logged and shown in the footer, not rethrown.
    public static func toggled(_ on: Bool, service: any LoginItemService) -> LoginItemToggle {
        do {
            if on { try service.register() } else { try service.unregister() }
            return LoginItemToggle(status: service.status)
        } catch {
            Logger(subsystem: "com.eightabyte.transom", category: "login")
                .error("login item \(on ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return LoginItemToggle(status: service.status, lastError: error.localizedDescription)
        }
    }
}
