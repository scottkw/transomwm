import AppKit

/// One straight (not premultiplied) colour, components 0...1.
nonisolated struct RGBA: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double
}

/// The app colour of fallback tiles (UI-SPEC Color): the only colour Transom computes rather than takes from the system.
enum AppColor {
    static let sampleSize = 16
    private static var cache: [String: NSColor] = [:]

    /// The mean of the most common of 12 hue buckets (30 degrees each, ties to the lower bucket) among pixels at least
    /// 50% opaque and 20% saturated. Under 10% surviving: the mean of every opaque pixel. Nil with no opaque pixel.
    nonisolated static func dominant(_ pixels: [RGBA]) -> RGBA? {
        let opaque = pixels.filter { $0.a >= 0.5 }
        guard !opaque.isEmpty else { return nil }
        var buckets = Array(repeating: [RGBA](), count: 12)
        for pixel in opaque {
            let high = max(pixel.r, pixel.g, pixel.b), low = min(pixel.r, pixel.g, pixel.b)
            guard high > 0, (high - low) / high >= 0.2 else { continue }
            buckets[min(11, Int(hue(pixel, high: high, low: low) / 30))].append(pixel)
        }
        let surviving = buckets.reduce(0) { $0 + $1.count }
        guard Double(surviving) >= Double(pixels.count) * 0.1 else { return mean(opaque) }
        // max(by:) keeps the last of equal elements, so compare (count, -index) to send ties to the lower bucket.
        let winner = buckets.indices.max { (buckets[$0].count, -$0) < (buckets[$1].count, -$1) } ?? 0
        return mean(buckets[winner])
    }

    /// The app colour for `bundleID`, computed once from `icon` downsampled to 16x16; `systemGray` without an icon.
    static func color(forBundleID bundleID: String, icon: NSImage?) -> NSColor {
        if let cached = cache[bundleID] { return cached }
        let color = icon.flatMap(pixels).flatMap(dominant).map { NSColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: 1) } ?? .systemGray
        cache[bundleID] = color
        return color
    }

    /// The icon drawn into a 16x16 sRGB bitmap, un-premultiplied.
    private static func pixels(_ icon: NSImage) -> [RGBA]? {
        let size = sampleSize
        var rect = NSRect(x: 0, y: 0, width: size, height: size)
        guard let image = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let data = { context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size)); return context.data }()
        else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: size * size * 4)
        return (0..<size * size).map { i in
            let a = Double(bytes[i * 4 + 3]) / 255
            guard a > 0 else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
            func channel(_ offset: Int) -> Double { min(1, Double(bytes[i * 4 + offset]) / 255 / a) }
            return RGBA(r: channel(0), g: channel(1), b: channel(2), a: a)
        }
    }

    /// HSV hue in degrees, 0..<360.
    nonisolated private static func hue(_ p: RGBA, high: Double, low: Double) -> Double {
        let span = high - low
        let degrees: Double
        if high == p.r {
            degrees = 60 * ((p.g - p.b) / span)
        } else if high == p.g {
            degrees = 60 * ((p.b - p.r) / span) + 120
        } else {
            degrees = 60 * ((p.r - p.g) / span) + 240
        }
        return degrees < 0 ? degrees + 360 : degrees
    }

    nonisolated private static func mean(_ pixels: [RGBA]) -> RGBA {
        let n = Double(pixels.count)
        return RGBA(
            r: pixels.reduce(0) { $0 + $1.r } / n, g: pixels.reduce(0) { $0 + $1.g } / n, b: pixels.reduce(0) { $0 + $1.b } / n, a: 1)
    }
}
