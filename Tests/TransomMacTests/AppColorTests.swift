import AppKit
@testable import TransomMac
import Testing

private let red = RGBA(r: 0.9, g: 0.1, b: 0.1, a: 1)
private let blue = RGBA(r: 0.1, g: 0.2, b: 0.9, a: 1)
private let grey = RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1)
private let clear = RGBA(r: 0, g: 0, b: 0, a: 0)

private func near(_ a: RGBA?, _ b: RGBA, _ slack: Double = 1e-9) -> Bool {
    guard let a else { return false }
    return abs(a.r - b.r) < slack && abs(a.g - b.g) < slack && abs(a.b - b.b) < slack
}

/// A solid `size` x `size` image of one colour.
@MainActor private func icon(_ color: NSColor, size: Int = 32) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        color.setFill()
        rect.fill()
        return true
    }
}

/// UI-SPEC Color, App colour: the dominant hue of a 16x16 icon.
@Suite struct AppColorTests {
    @Test func aMostlyRedIconGivesARedMean() {
        let pixels = Array(repeating: red, count: 200) + Array(repeating: blue, count: 56)
        #expect(near(AppColor.dominant(pixels), red))
    }

    @Test func lowAlphaAndLowSaturationPixelsAreIgnored() {
        let faintBlue = RGBA(r: 0.1, g: 0.2, b: 0.9, a: 0.4)
        let pixels = Array(repeating: red, count: 60) + Array(repeating: faintBlue, count: 100) + Array(repeating: grey, count: 96)
        #expect(near(AppColor.dominant(pixels), red))
    }

    @Test func theMeanIsTakenWithinTheWinningBucket() {
        let darker = RGBA(r: 0.7, g: 0.1, b: 0.1, a: 1)
        let pixels = Array(repeating: red, count: 100) + Array(repeating: darker, count: 100) + Array(repeating: blue, count: 56)
        #expect(near(AppColor.dominant(pixels), RGBA(r: 0.8, g: 0.1, b: 0.1, a: 1)))
    }

    @Test func aMonochromeIconGivesTheMeanOfAllOpaquePixels() {
        let black = RGBA(r: 0, g: 0, b: 0, a: 1), white = RGBA(r: 1, g: 1, b: 1, a: 1)
        // 20 saturated pixels of 256 is under 10%, so the opaque mean wins.
        let pixels = Array(repeating: black, count: 100) + Array(repeating: white, count: 100) + Array(repeating: red, count: 20)
            + Array(repeating: clear, count: 36)
        let mean = RGBA(r: (100 + 20 * 0.9) / 220, g: (100 + 20 * 0.1) / 220, b: (100 + 20 * 0.1) / 220, a: 1)
        #expect(near(AppColor.dominant(pixels), mean))
    }

    @Test func anAllTransparentIconGivesNil() {
        #expect(AppColor.dominant(Array(repeating: clear, count: 256)) == nil)
        #expect(AppColor.dominant([]) == nil)
    }

    @Test func aTieGoesToTheLowerBucket() {
        // Red (hue 0, bucket 0) and blue (hue about 233, bucket 7), 128 each.
        let pixels = Array(repeating: blue, count: 128) + Array(repeating: red, count: 128)
        #expect(near(AppColor.dominant(pixels), red))
    }

    @MainActor @Test func theColourIsComputedOncePerBundleID() throws {
        let bundleID = "test.appcolor.\(UInt32.random(in: 0...UInt32.max))"
        let first = AppColor.color(forBundleID: bundleID, icon: icon(.systemRed))
        let second = AppColor.color(forBundleID: bundleID, icon: icon(.systemBlue))
        #expect(first == second)
        let rgb = try #require(first.usingColorSpace(.sRGB))
        #expect(rgb.redComponent > 0.8 && rgb.blueComponent < 0.4)
    }

    @MainActor @Test func noIconGivesSystemGray() {
        #expect(AppColor.color(forBundleID: "test.appcolor.none.\(UInt32.random(in: 0...UInt32.max))", icon: nil) == .systemGray)
    }
}

/// A `width` x `height` image (its decoded size is width * height * 4 bytes).
private func image(_ width: Int, _ height: Int) throws -> CGImage {
    let context = try #require(
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    return try #require(context.makeImage())
}

/// UI-SPEC Surface 2: the snapshot cache is an LRU of decoded bytes, capped at 128 MB.
@Suite struct SnapshotCacheTests {
    @Test func theCapacityIs128MB() {
        #expect(SnapshotCache.capacity == 128 * 1024 * 1024)
        #expect(SnapshotCache().capacityBytes == SnapshotCache.capacity)
    }

    @Test func insertingPastTheCapacityEvictsTheLeastRecentlyUsedFirst() throws {
        var cache = SnapshotCache(capacity: 3 * 100 * 4)  // three 10x10 images
        for id: UInt32 in 1...3 { cache.insert(try image(10, 10), for: id) }
        #expect(cache.count == 3 && cache.bytes == 1200)
        cache.insert(try image(10, 10), for: 4)
        #expect(cache.image(for: 1) == nil)
        #expect(cache.image(for: 2) != nil && cache.image(for: 3) != nil && cache.image(for: 4) != nil)
        #expect(cache.bytes == 1200)
    }

    @Test func readingAnEntryRefreshesItsRecency() throws {
        var cache = SnapshotCache(capacity: 3 * 100 * 4)
        for id: UInt32 in 1...3 { cache.insert(try image(10, 10), for: id) }
        _ = cache.image(for: 1)
        cache.insert(try image(10, 10), for: 4)
        #expect(cache.image(for: 1) != nil)
        #expect(cache.image(for: 2) == nil)
    }

    @Test func replacingAnEntryCountsOnlyItsNewSize() throws {
        var cache = SnapshotCache(capacity: 10_000)
        cache.insert(try image(10, 10), for: 1)
        cache.insert(try image(20, 10), for: 1)
        #expect(cache.count == 1 && cache.bytes == 800)
    }

    @Test func anImageLargerThanTheCapacityIsNotKept() throws {
        var cache = SnapshotCache(capacity: 100)
        cache.insert(try image(10, 10), for: 1)
        #expect(cache.count == 0 && cache.bytes == 0)
    }

    @Test func removeDropsOneAndPurgeEmptiesIt() throws {
        var cache = SnapshotCache(capacity: 10_000)
        for id: UInt32 in 1...3 { cache.insert(try image(10, 10), for: id) }
        cache.remove(2)
        #expect(cache.count == 2 && cache.bytes == 800 && cache.image(for: 2) == nil)
        cache.purge()
        #expect(cache.count == 0 && cache.bytes == 0)
    }
}
