import Foundation
import TransomEngine
@testable import TransomMac
import Testing

/// One canned releases/latest response per request, counted. Tests never reach the network.
private final class ScheduleStubProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var requests = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"tag_name": "v0.8.0", "draft": false, "prerelease": false, "assets": []}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The daily automatic check (D-09) with an injected sleep, and the Debug "Updates" line.
@Suite(.serialized) @MainActor struct UpdateScheduleTests {
    let suite = "com.eightabyte.transom.tests.schedule.\(UUID().uuidString)"

    init() {
        ScheduleStubProtocol.status = 200
        ScheduleStubProtocol.requests = 0
    }

    private func controller() throws -> UpdateController {
        let configuration = GitHubReleaseClient.configuration()
        configuration.protocolClasses = [ScheduleStubProtocol.self]
        let defaults = try #require(UserDefaults(suiteName: suite))
        return UpdateController(
            client: GitHubReleaseClient(configuration: configuration, userAgent: "Transom/0.8.0"), currentVersion: "0.8.0",
            build: "1", isEnabled: true, defaults: defaults)
    }

    @Test func theFirstCheckIsTenSecondsAfterLaunchThenDaily() async throws {
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let updates = try controller()
        var waits: [Duration] = []
        updates.startAutomatic { wait in
            waits.append(wait)
            if waits.count == 3 { throw CancellationError() }
        }
        await updates.automaticTask?.value
        #expect(waits == [.seconds(10), .seconds(86_400), .seconds(86_400)])
        #expect(ScheduleStubProtocol.requests == 2)
        #expect(updates.status == .current("0.8.0"))
        #expect(updates.lastChecked != nil)
    }

    @Test func turningAutomaticOffStopsTheSchedule() async throws {
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let updates = try controller()
        var waits: [Duration] = []
        updates.startAutomatic { wait in
            waits.append(wait)
            if waits.count == 1 { updates.automatic = false }  // cancels this round before its check
            if waits.count == 2 { throw CancellationError() }
        }
        let first = updates.automaticTask
        await first?.value
        #expect(updates.automaticTask == nil)
        #expect(ScheduleStubProtocol.requests == 0)
        updates.automatic = true
        await updates.automaticTask?.value
        #expect(waits == [.seconds(10), .seconds(10)])
        #expect(ScheduleStubProtocol.requests == 0)
    }

    @Test func anAutomaticFailureIsSilent() async throws {
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        ScheduleStubProtocol.status = 500
        let updates = try controller()
        var waits = 0
        updates.startAutomatic { _ in
            waits += 1
            if waits == 2 { throw CancellationError() }
        }
        await updates.automaticTask?.value
        #expect(ScheduleStubProtocol.requests == 1)
        #expect(updates.error == nil)
        #expect(updates.status == .idle)
        #expect(updates.lastChecked != nil)
    }

    @Test func theDebugLineShowsStateAndLastCheck() throws {
        #expect(UpdateCopy.debugLine(status: .current("0.9.0"), lastChecked: nil) == "Updates: current, last checked never")
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 9, minute: 5)))
        #expect(UpdateCopy.debugLine(status: .idle, lastChecked: date) == "Updates: idle, last checked 09:05")
        let release = UpdateRelease(
            version: "0.9.1", url: URL(string: "https://github.com/scottkw/transomwm/releases/download/v0.9.1/x.dmg")!, size: 1,
            sha256: "ab")
        #expect(UpdateCopy.debugLine(status: .available(release), lastChecked: nil) == "Updates: 0.9.1 available, last checked never")
    }
}
