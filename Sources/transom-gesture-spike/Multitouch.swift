import CoreFoundation
import Darwin
import Foundation
import IOKit
import os

/// Spike-only MultitouchSupport shim (E-01: it moves into TransomPrivate only if the user picks multitouch at the gate,
/// plan 05-07). Reached by `dlopen` + `dlsym` into optional `@convention(c)` pointers, never linked, so a missing symbol
/// is a nil, not a launch failure.
///
/// Provenance (prototypes and layout, read as facts, never copied): OpenMultitouchSupport `OpenMTInternal.h` (MIT),
/// Mac-trackpad-mapper `MultitouchSupport.h` and ScrollToZoom `MTSupportSPI.h` (MIT); OMS issues #2 (over-release crash
/// after wake), #6 (default device sees one trackpad) and #13 (a `void` callback stops system gestures on macOS 27).
/// Rules: the callback returns Int32 and always 0; the touch count is bounded to 0...20 and the pointer nil-checked
/// before reading the 96-byte stride; devices from the list are never released (the list owns them); devices are started
/// and stopped on one dedicated CFRunLoop thread.
nonisolated enum Multitouch {
    typealias Device = UnsafeMutableRawPointer
    typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    /// (device, touches, count, timestamp, frame, refcon). Count and frame are declared Int32: the lineages disagree
    /// (int, size_t, CFIndex), and the low 32 bits of the register are right either way on arm64 and x86_64.
    typealias FrameCallback = @convention(c) (Device?, UnsafeRawPointer?, Int32, Double, Int32, UnsafeMutableRawPointer?) -> Int32
    /// The register without a refcon calls back with the first five arguments only.
    typealias PlainFrameCallback = @convention(c) (Device?, UnsafeRawPointer?, Int32, Double, Int32) -> Int32
    typealias RegisterWithRefcon = @convention(c) (Device, FrameCallback, UnsafeMutableRawPointer?) -> Void
    typealias Register = @convention(c) (Device, PlainFrameCallback) -> Void
    typealias Unregister = @convention(c) (Device, UnsafeRawPointer) -> Void
    typealias Start = @convention(c) (Device, Int32) -> Int32
    typealias Stop = @convention(c) (Device) -> Int32
    typealias IsBuiltIn = @convention(c) (Device) -> Bool
    typealias GetInt32 = @convention(c) (Device, UnsafeMutablePointer<Int32>) -> Int32
    typealias GetUInt64 = @convention(c) (Device, UnsafeMutablePointer<UInt64>) -> Int32
    typealias GetDimensions = @convention(c) (Device, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32
    typealias GetService = @convention(c) (Device) -> io_service_t

    /// OMS `MTTouch`, 96 bytes (four header lineages agree): identifier 16, state 20, normalized x/y 32/36, velocity 40/44.
    static let touchStride = 96
    static let maxTouches = 20
    /// Magic Mouse is a multitouch device too, but never a trackpad (ScrollToZoom `kMTDeviceFamilyMagicMouse = 112`).
    static let magicMouseFamily: Int32 = 112

    static let symbolNames = [
        "MTDeviceCreateList", "MTRegisterContactFrameCallbackWithRefcon", "MTRegisterContactFrameCallback",
        "MTUnregisterContactFrameCallback", "MTDeviceStart", "MTDeviceStop", "MTDeviceIsBuiltIn", "MTDeviceGetFamilyID",
        "MTDeviceGetDeviceID", "MTDeviceGetSensorSurfaceDimensions", "MTDeviceGetService", "MTDeviceGetDriverType",
    ]

    /// Written once at first use, then only read.
    nonisolated(unsafe) private static let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY)
    private static func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    static let createList = symbol("MTDeviceCreateList", CreateList.self)
    static let registerWithRefcon = symbol("MTRegisterContactFrameCallbackWithRefcon", RegisterWithRefcon.self)
    static let register = symbol("MTRegisterContactFrameCallback", Register.self)
    static let unregister = symbol("MTUnregisterContactFrameCallback", Unregister.self)
    static let start = symbol("MTDeviceStart", Start.self)
    static let stop = symbol("MTDeviceStop", Stop.self)
    static let isBuiltIn = symbol("MTDeviceIsBuiltIn", IsBuiltIn.self)
    static let familyID = symbol("MTDeviceGetFamilyID", GetInt32.self)
    static let deviceID = symbol("MTDeviceGetDeviceID", GetUInt64.self)
    static let dimensions = symbol("MTDeviceGetSensorSurfaceDimensions", GetDimensions.self)
    static let service = symbol("MTDeviceGetService", GetService.self)
    static let driverType = symbol("MTDeviceGetDriverType", GetInt32.self)

    /// The `dlsym` table for `mt-devices`: name and whether it resolved.
    static func symbolTable() -> [(String, Bool)] {
        symbolNames.map { name in (name, handle.flatMap { dlsym($0, name) } != nil) }
    }

    struct Info: Sendable {
        let index: Int
        let builtIn: Bool
        let family: Int32
        let deviceID: UInt64
        let registryID: UInt64
        let widthMM: Double
        let heightMM: Double
        let driverType: Int32
        var isTrackpad: Bool { family != Multitouch.magicMouseFamily }
        var name: String { builtIn ? "built-in" : isTrackpad ? "Magic Trackpad" : "Magic Mouse" }
    }

    struct Touch: Sendable {
        let id: Int32
        let state: Int32
        let x: Float
        let y: Float
        let vx: Float
        let vy: Float
    }

    struct Frame: Sendable {
        let device: Int
        /// Uptime-clock seconds when the callback ran; `deviceTime` is the callback's own timestamp argument.
        let t: Double
        let deviceTime: Double
        let frame: Int32
        let rawCount: Int32
        let touches: [Touch]
        let mainThread: Bool
    }

    /// One device list. The array owns its devices, so it stays alive while they run and is dropped only after stop.
    final class DeviceList: @unchecked Sendable {
        let array: CFArray?
        let devices: [Device]
        let infos: [Info]

        init() {
            array = Multitouch.createList?()?.takeRetainedValue()
            var devices: [Device] = []
            if let array {
                for index in 0..<CFArrayGetCount(array) {
                    if let pointer = CFArrayGetValueAtIndex(array, index) { devices.append(UnsafeMutableRawPointer(mutating: pointer)) }
                }
            }
            self.devices = devices
            infos = devices.enumerated().map { Multitouch.info($0.element, index: $0.offset) }
        }
    }

    static func info(_ device: Device, index: Int) -> Info {
        var family: Int32 = 0
        var id: UInt64 = 0
        var width: Int32 = 0
        var height: Int32 = 0
        var driver: Int32 = 0
        _ = familyID?(device, &family)
        _ = deviceID?(device, &id)
        _ = dimensions?(device, &width, &height)
        _ = driverType?(device, &driver)
        var registry: UInt64 = 0
        if let service, case let entry = service(device), entry != 0 { IORegistryEntryGetRegistryEntryID(entry, &registry) }
        return Info(
            index: index, builtIn: isBuiltIn?(device) ?? false, family: family, deviceID: id, registryID: registry,
            widthMM: Double(width) / 100, heightMM: Double(height) / 100, driverType: driver)
    }

    // MARK: Streaming

    /// Frames waiting for main, and the device index per device pointer (for the no-refcon fallback).
    static let frames = OSAllocatedUnfairLock(initialState: [Frame]())
    static let indexes = OSAllocatedUnfairLock(initialState: [UInt: Int]())

    static func receive(_ device: Device?, _ touches: UnsafeRawPointer?, _ count: Int32, _ timestamp: Double, _ frame: Int32, index: Int?) {
        let n = touches == nil ? 0 : max(0, min(Int(count), maxTouches))
        var decoded: [Touch] = []
        if let touches, n > 0 {
            decoded.reserveCapacity(n)
            for i in 0..<n {
                let base = touches + i * touchStride
                decoded.append(
                    Touch(
                        id: base.loadUnaligned(fromByteOffset: 16, as: Int32.self), state: base.loadUnaligned(fromByteOffset: 20, as: Int32.self),
                        x: base.loadUnaligned(fromByteOffset: 32, as: Float.self), y: base.loadUnaligned(fromByteOffset: 36, as: Float.self),
                        vx: base.loadUnaligned(fromByteOffset: 40, as: Float.self), vy: base.loadUnaligned(fromByteOffset: 44, as: Float.self)))
            }
        }
        let key = device.map { UInt(bitPattern: $0) }
        let resolved = index ?? key.flatMap { key in indexes.withLock { $0[key] } } ?? -1
        let record = Frame(
            device: resolved, t: Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9, deviceTime: timestamp, frame: frame, rawCount: count,
            touches: decoded, mainThread: Thread.isMainThread)
        frames.withLock { $0.append(record) }
    }

    /// One stable C function pointer each, so unregister gets the same pointer register got.
    static let callback: FrameCallback = { device, touches, count, timestamp, frame, refcon in
        Multitouch.receive(device, touches, count, timestamp, frame, index: refcon.map { Int(bitPattern: $0) - 1 })
        return 0  // never consume: system gestures must keep their frames (Pitfall 8)
    }
    static let plainCallback: PlainFrameCallback = { device, touches, count, timestamp, frame in
        Multitouch.receive(device, touches, count, timestamp, frame, index: nil)
        return 0
    }

    /// The dedicated thread every start and stop runs on.
    final class Worker: @unchecked Sendable {
        private var runLoop: CFRunLoop?

        init() {
            let ready = DispatchSemaphore(value: 0)
            let thread = Thread { [self] in
                runLoop = CFRunLoopGetCurrent()
                // A port keeps the run loop alive with no other source.
                CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(nil, CFMachPortCreate(nil, nil, nil, nil), 0), .commonModes)
                ready.signal()
                CFRunLoopRun()
            }
            thread.name = "GestureSpikeMultitouch"
            thread.qualityOfService = .userInteractive
            thread.start()
            ready.wait()
        }

        /// Runs `work` on the worker thread and waits for it.
        func sync(_ work: @escaping @Sendable () -> Void) {
            guard let runLoop else { return }
            let done = DispatchSemaphore(value: 0)
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                work()
                done.signal()
            }
            CFRunLoopWakeUp(runLoop)
            done.wait()
        }
    }

    /// Registers and starts every device of `list` (trackpads only unless `all`), on the worker thread. False when the
    /// needed symbols are missing.
    /// Frames carry `tagBase + index` as their device, so a rescan's generations stay apart.
    static func startStreaming(_ list: DeviceList, on worker: Worker, tagBase: Int = 0, all: Bool = false) -> Bool {
        guard let start, registerWithRefcon != nil || register != nil else { return false }
        let chosen = list.infos.filter { all || $0.isTrackpad }
        indexes.withLock { map in for info in chosen { map[UInt(bitPattern: list.devices[info.index])] = tagBase + info.index } }
        worker.sync {
            for info in chosen {
                let device = list.devices[info.index]
                if let registerWithRefcon {
                    registerWithRefcon(device, callback, UnsafeMutableRawPointer(bitPattern: tagBase + info.index + 1))
                } else {
                    register?(device, plainCallback)
                }
                _ = start(device, 0)
            }
        }
        return true
    }

    /// Stops and unregisters every device of `list` on the worker thread. The list's array is released by its owner
    /// afterwards; no device is ever released on its own.
    static func stopStreaming(_ list: DeviceList, on worker: Worker) {
        worker.sync {
            for device in list.devices {
                if let unregister {
                    let pointer = registerWithRefcon != nil
                        ? unsafeBitCast(callback, to: UnsafeRawPointer.self) : unsafeBitCast(plainCallback, to: UnsafeRawPointer.self)
                    unregister(device, pointer)
                }
                _ = stop?(device)
            }
        }
    }

    static func takeFrames() -> [Frame] { frames.withLock { pending in defer { pending = [] }; return pending } }
}
