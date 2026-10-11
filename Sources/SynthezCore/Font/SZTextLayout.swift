//
//  SZTextLayout.swift
//  SynthezCore
//

/// Text broken into lines for a width.
public struct SZTextLayout: Sendable {
    public var lines: [Substring]
    /// The widest line.
    public var width: Int
    public var lineHeight: Int

    public var height: Int {
        lines.count * lineHeight
    }
}

public enum SZTextWrap: Hashable, Sendable {
    /// One line per hard break.
    case none
    /// Breaks at spaces, and inside words longer than a line.
    case word
    /// Breaks anywhere.
    case character
}

public extension SZBitmapFont {
    /// Greedy line breaking: as many words per line as fit `width`.
    func layout(_ text: String, width: Int, scale: Int = 1, wrap: SZTextWrap = .word) -> SZTextLayout {
        let scale = max(scale, 1)
        let limit = max(width / scale, 1)
        var lines: [Substring] = []
        var widest = 0
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard wrap != .none, measure(paragraph) > limit else {
                lines.append(paragraph)
                widest = max(widest, measure(paragraph))
                continue
            }
            var start = paragraph.startIndex
            while start < paragraph.endIndex {
                var end = start
                var lastSpace: Substring.Index?
                var lineWidth = 0
                var index = start
                while index < paragraph.endIndex {
                    let ch = paragraph[index]
                    let glyphWidth = ch.unicodeScalars.reduce(0) { $0 + glyphs[Int(glyphIndex(for: $1.value))].width }
                    let next = lineWidth + (index == start ? 0 : spacing) + glyphWidth
                    if next > limit, index > start {
                        break
                    }
                    lineWidth = next
                    if ch == " " {
                        lastSpace = index
                    }
                    index = paragraph.index(after: index)
                    end = index
                }
                if end < paragraph.endIndex, wrap == .word, let space = lastSpace, space > start {
                    end = space
                }
                let line = paragraph[start ..< end]
                let trimmed = line.hasSuffix(" ") ? line.dropLast() : line
                lines.append(trimmed)
                widest = max(widest, measure(trimmed))
                start = end
                while start < paragraph.endIndex, paragraph[start] == " " {
                    start = paragraph.index(after: start)
                }
            }
        }
        return SZTextLayout(lines: lines, width: widest * scale, lineHeight: lineHeight * scale)
    }
}

/// Keeps wrapped text between frames, the way Litext keeps measurements:
/// a layout is reused while the same text, font, width and scale are drawn,
/// and dropped a few frames after it stops being asked for.
public final class SZTextLayoutCache {
    private struct Key: Hashable {
        var text: String
        var font: ObjectIdentifier
        var width: Int
        var scale: Int
        var wrap: SZTextWrap
    }

    private struct Entry {
        var layout: SZTextLayout
        var frame: UInt64
    }

    private var entries: [Key: Entry] = [:]
    private var frame: UInt64 = 0
    /// Frames an unused layout survives.
    public var lifetime: UInt64 = 30
    public private(set) var hits = 0
    public private(set) var misses = 0

    public init() {}

    public var count: Int {
        entries.count
    }

    public func layout(_ text: String, font: SZBitmapFont, width: Int, scale: Int, wrap: SZTextWrap) -> SZTextLayout {
        let key = Key(text: text, font: ObjectIdentifier(font), width: width, scale: scale, wrap: wrap)
        if var entry = entries[key] {
            if entry.frame != frame {
                entry.frame = frame
                entries[key] = entry
            }
            hits += 1
            return entry.layout
        }
        misses += 1
        let layout = font.layout(text, width: width, scale: scale, wrap: wrap)
        entries[key] = Entry(layout: layout, frame: frame)
        return layout
    }

    func endFrame(_ number: UInt64) {
        frame = number
        guard number % 30 == 0, !entries.isEmpty else { return }
        let lifetime = lifetime
        entries = entries.filter { number - $0.value.frame <= lifetime }
    }
}
