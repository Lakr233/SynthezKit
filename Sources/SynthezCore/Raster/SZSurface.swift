//
//  SZSurface.swift
//  SynthezCore
//

/// A CPU framebuffer of palette indices, one byte per virtual pixel.
///
/// Rasterizing a whole 640×400 frame touches 256 KB, which keeps the CPU
/// path cheaper than round trips to the GPU and lets ``SZDrawOp/remap`` and
/// ``SZDrawOp/mosaic`` read back what was drawn before them.
///
/// - Important: Performance-sensitive. Every primitive clips first and then
///   writes through an unsafe buffer pointer.
public final class SZSurface {
    public private(set) var width: Int
    public private(set) var height: Int
    public private(set) var pixels: [UInt8]

    public init(width: Int, height: Int) {
        self.width = max(width, 0)
        self.height = max(height, 0)
        pixels = [UInt8](repeating: 0, count: self.width * self.height)
    }

    public var bounds: SZRect {
        SZRect(0, 0, width, height)
    }

    public func resize(width: Int, height: Int) {
        let width = max(width, 0), height = max(height, 0)
        guard width != self.width || height != self.height else { return }
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height)
    }

    @inlinable public subscript(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }

    // MARK: - Replay

    /// Clears to the list's background and replays every layer.
    public func render(_ list: SZDrawList) {
        clear(list.background)
        let clips = list.clips.map { $0.intersection(bounds) }
        for layer in list.layers {
            for command in layer {
                draw(command.op, clip: clips[Int(command.clip)], list: list)
            }
        }
    }

    public func clear(_ color: SZColor) {
        pixels.withUnsafeMutableBufferPointer { $0.update(repeating: color) }
    }

    @inline(__always)
    private func draw(_ op: SZDrawOp, clip: SZRect, list: SZDrawList) {
        guard !clip.isEmpty else { return }
        switch op {
        case let .fill(rect, color, pattern):
            fill(rect, color: color, pattern: pattern, clip: clip)
        case let .stroke(rect, color):
            guard rect.width > 0, rect.height > 0 else { return }
            fill(SZRect(rect.x, rect.y, rect.width, 1), color: color, pattern: SZPatterns.solid, clip: clip)
            fill(SZRect(rect.x, rect.maxY - 1, rect.width, 1), color: color, pattern: SZPatterns.solid, clip: clip)
            fill(SZRect(rect.x, rect.y, 1, rect.height), color: color, pattern: SZPatterns.solid, clip: clip)
            fill(SZRect(rect.maxX - 1, rect.y, 1, rect.height), color: color, pattern: SZPatterns.solid, clip: clip)
        case let .line(a, b, color):
            line(a, b, color: color, clip: clip)
        case let .circle(center, radius, color, filled):
            circle(center, radius: radius, color: color, filled: filled, clip: clip)
        case let .pixel(p, color):
            if clip.contains(p) {
                pixels[p.y * width + p.x] = color
            }
        case let .bitmap(bitmap, origin, color, scale):
            blit(bitmap, at: origin, color: color, scale: scale, clip: clip)
        case let .text(fontSlot, range, origin, color, scale):
            let font = list.fonts[Int(fontSlot)]
            var x = origin.x
            let step = font.spacing * scale
            list.glyphs.withUnsafeBufferPointer { glyphs in
                for i in Int(range.lowerBound) ..< Int(range.upperBound) {
                    let glyph = font.glyphs[Int(glyphs[i])]
                    if x >= clip.maxX {
                        break
                    }
                    if x + glyph.width * scale > clip.minX {
                        blit(glyph, at: SZPoint(x, origin.y), color: color, scale: scale, clip: clip)
                    }
                    x += glyph.width * scale + step
                }
            }
        case let .remap(rect, map, pattern):
            remap(rect, map: map, pattern: pattern, clip: clip)
        case let .mosaic(rect, size):
            mosaic(rect, size: size, clip: clip)
        case let .filter(rect, field, maps, blend):
            filter(rect, field: field, maps: maps, blend: blend, clip: clip)
        }
    }

    // MARK: - Primitives

    public func fill(_ rect: SZRect, color: SZColor, pattern: SZPattern, clip: SZRect) {
        let r = rect.intersection(clip)
        guard !r.isEmpty, pattern != 0 else { return }
        let width = width
        pixels.withUnsafeMutableBufferPointer { buffer in
            if pattern == SZPatterns.solid {
                for y in r.minY ..< r.maxY {
                    let row = y * width
                    UnsafeMutableBufferPointer(rebasing: buffer[(row + r.minX) ..< (row + r.maxX)]).update(repeating: color)
                }
            } else {
                for y in r.minY ..< r.maxY {
                    let row = y * width
                    let bits = pattern >> SZPattern((y & 3) << 2)
                    for x in r.minX ..< r.maxX where bits & (1 << SZPattern(x & 3)) != 0 {
                        buffer[row + x] = color
                    }
                }
            }
        }
    }

    public func blit(_ bitmap: SZBitmap, at origin: SZPoint, color: SZColor, scale: Int, clip: SZRect) {
        let scale = max(scale, 1)
        let r = SZRect(origin.x, origin.y, bitmap.width * scale, bitmap.height * scale).intersection(clip)
        guard !r.isEmpty else { return }
        let width = width
        pixels.withUnsafeMutableBufferPointer { buffer in
            bitmap.rows.withUnsafeBufferPointer { rows in
                for y in r.minY ..< r.maxY {
                    let bits = rows[(y - origin.y) / scale]
                    guard bits != 0 else { continue }
                    let row = y * width
                    if scale == 1 {
                        for x in r.minX ..< r.maxX where bits & (1 << UInt64(x - origin.x)) != 0 {
                            buffer[row + x] = color
                        }
                    } else {
                        for x in r.minX ..< r.maxX where bits & (1 << UInt64((x - origin.x) / scale)) != 0 {
                            buffer[row + x] = color
                        }
                    }
                }
            }
        }
    }

    public func line(_ a: SZPoint, _ b: SZPoint, color: SZColor, clip: SZRect) {
        if a.y == b.y {
            fill(SZRect(min(a.x, b.x), a.y, abs(b.x - a.x) + 1, 1), color: color, pattern: SZPatterns.solid, clip: clip)
            return
        }
        if a.x == b.x {
            fill(SZRect(a.x, min(a.y, b.y), 1, abs(b.y - a.y) + 1), color: color, pattern: SZPatterns.solid, clip: clip)
            return
        }
        var x = a.x, y = a.y
        let dx = abs(b.x - a.x), dy = -abs(b.y - a.y)
        let sx = a.x < b.x ? 1 : -1, sy = a.y < b.y ? 1 : -1
        var err = dx + dy
        while true {
            if clip.contains(SZPoint(x, y)) {
                pixels[y * width + x] = color
            }
            if x == b.x, y == b.y {
                break
            }
            let e2 = 2 * err
            if e2 >= dy {
                err += dy; x += sx
            }
            if e2 <= dx {
                err += dx; y += sy
            }
        }
    }

    public func circle(_ c: SZPoint, radius: Int, color: SZColor, filled: Bool, clip: SZRect) {
        guard radius >= 0 else { return }
        var x = radius, y = 0, err = 1 - radius
        func span(_ x0: Int, _ x1: Int, _ y: Int) {
            fill(SZRect(x0, y, x1 - x0 + 1, 1), color: color, pattern: SZPatterns.solid, clip: clip)
        }
        func plot(_ px: Int, _ py: Int) {
            if clip.contains(SZPoint(px, py)) {
                pixels[py * width + px] = color
            }
        }
        while x >= y {
            if filled {
                span(c.x - x, c.x + x, c.y + y)
                span(c.x - x, c.x + x, c.y - y)
                span(c.x - y, c.x + y, c.y + x)
                span(c.x - y, c.x + y, c.y - x)
            } else {
                plot(c.x + x, c.y + y); plot(c.x - x, c.y + y)
                plot(c.x + x, c.y - y); plot(c.x - x, c.y - y)
                plot(c.x + y, c.y + x); plot(c.x - y, c.y + x)
                plot(c.x + y, c.y - x); plot(c.x - y, c.y - x)
            }
            y += 1
            if err < 0 {
                err += 2 * y + 1
            } else {
                x -= 1
                err += 2 * (y - x) + 1
            }
        }
    }

    public func remap(_ rect: SZRect, map: SZColorMap, pattern: SZPattern, clip: SZRect) {
        let r = rect.intersection(clip)
        guard !r.isEmpty, pattern != 0 else { return }
        let width = width
        pixels.withUnsafeMutableBufferPointer { buffer in
            map.table.withUnsafeBufferPointer { table in
                for y in r.minY ..< r.maxY {
                    let row = y * width
                    let bits = pattern >> SZPattern((y & 3) << 2)
                    for x in r.minX ..< r.maxX where bits & (1 << SZPattern(x & 3)) != 0 {
                        buffer[row + x] = table[Int(buffer[row + x])]
                    }
                }
            }
        }
    }

    public func filter(_ rect: SZRect, field: SZStrengthField, maps: SZFilterMaps, blend: SZFilterBlend, clip: SZRect) {
        let r = rect.intersection(clip)
        guard !r.isEmpty, let full = maps.maps.last else { return }
        let width = width
        let levels = maps.maps.count - 1
        if case let .constant(s) = field {
            // One map for the whole rectangle.
            switch blend {
            case .steps:
                remap(r, map: maps.maps[Int((min(max(s, 0), 1) * Double(levels)).rounded())], pattern: SZPatterns.solid, clip: clip)
            case .dither:
                remap(r, map: full, pattern: SZPatterns.shade(s), clip: clip)
            }
            return
        }
        pixels.withUnsafeMutableBufferPointer { buffer in
            for y in r.minY ..< r.maxY {
                let row = y * width
                for x in r.minX ..< r.maxX {
                    let s = min(max(field.strength(x, y), 0), 1)
                    switch blend {
                    case .dither:
                        let threshold = Int(SZPatterns.bayer[(y & 3) << 2 | (x & 3)])
                        if threshold < Int((s * 16).rounded()) {
                            buffer[row + x] = full.table[Int(buffer[row + x])]
                        }
                    case .steps:
                        let level = Int((s * Double(levels)).rounded())
                        if level > 0 {
                            buffer[row + x] = maps.maps[level].table[Int(buffer[row + x])]
                        }
                    }
                }
            }
        }
    }

    public func mosaic(_ rect: SZRect, size: Int, clip: SZRect) {
        guard size > 1 else { return }
        let r = rect.intersection(clip)
        guard !r.isEmpty else { return }
        let width = width
        pixels.withUnsafeMutableBufferPointer { buffer in
            var by = r.minY
            while by < r.maxY {
                let bh = min(size, r.maxY - by)
                var bx = r.minX
                while bx < r.maxX {
                    let bw = min(size, r.maxX - bx)
                    let color = buffer[(by + bh / 2) * width + bx + bw / 2]
                    for y in by ..< by + bh {
                        UnsafeMutableBufferPointer(rebasing: buffer[(y * width + bx) ..< (y * width + bx + bw)]).update(repeating: color)
                    }
                    bx += size
                }
                by += size
            }
        }
    }
}
