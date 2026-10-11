//
//  SZGallery.swift
//  SynthezGallery
//

import Foundation
import SynthezCore
import SynthezWidgets

/// The demo app shared by the example app, the benchmark and the tests:
/// five pages behind a tab bar, a status line and tooltips.
public final class SZGallery {
    public enum Page: Int, CaseIterable, Sendable {
        case core
        case controls
        case text
        case scroll
        case crt

        var title: String {
            switch self {
            case .core: "CORE"
            case .controls: "CONTROLS"
            case .text: "TEXT"
            case .scroll: "SCROLL"
            case .crt: "CRT"
            }
        }
    }

    public var page = Page.core
    public var crt = SZCRTSettings()
    /// Extra pads on the controls page, to load the frame for benchmarks.
    public var gridCount: Int

    // Status messages.
    var message: String?
    var messageSerial = 0

    // Core page.
    var count = 0
    var loop = true
    var swapped = false
    var waveform = 0
    var playing = false
    var animateFilters = false
    var drums: Set<Int> = [0, 2]
    var sheetOpen = false
    var picked: String?
    var starred: Set<Int> = [1]
    var menuOpen = false

    // Controls page.
    var genres: Set<Int> = [0, 3]
    var waveChip = 1
    var mute = false
    var solo = true
    var colorIndex = 2
    var octave = 4
    var division = 0
    var bpm = 120.0
    var swing = 0.5
    var filterType: Int? = 0
    var editMenuOpen = false
    var knobs: [Double] = [0.62, 0.3, 0.45, 0.5, 0.25]
    var cutoff = 0.35
    var balance = 0.0
    var eq: [Double] = [0.5, 0.7, 0.4, 0.6]
    var pad = 0
    var on = true

    // Text page.
    var title = "UNTITLED SONG"
    var name = ""
    var digits = "128"
    var note = "A LONG NOTE THAT KEEPS GOING PAST THE EDGE OF ITS FIELD"
    var log: [String] = []
    var alignment = 0

    // Scroll page.
    var selectedRow: Int? = 3
    var channels: [Double] = (0 ..< 16).map { 0.3 + 0.4 * abs(sin(Double($0) * 1.7)) }

    public init(gridCount: Int = 32) {
        self.gridCount = gridCount
    }

    public static let resolution = SZResolution.fixed(width: 640, height: 400)

    func post(_ text: String) {
        message = text
        messageSerial += 1
    }

    public func draw(_ ctx: inout SZContext) {
        let theme = ctx.theme
        ctx.fill(ctx.bounds, color: theme.background)
        ctx.inset(top: 6, right: 6, bottom: 0, left: 6)

        // Header: name, page count and the CRT switch.
        let header = ctx.cutTop(11, gap: 4)
        ctx.region(header) { bar in
            let toggle = bar.cutRight(11)
            if iconButton(&bar, SZIcons.screen, label: "CRT", on: crt.isEnabled, hint: "TOGGLE THE CRT FILTER", key: "crt-toggle", in: toggle).clicked {
                crt.isEnabled.toggle()
                post(crt.isEnabled ? "CRT ON" : "CRT OFF")
            }
            bar.flow = .horizontal
            bar.gap = 6
            bar.align = .center
            label(&bar, "SYNTH-KIT", color: theme.accent)
            label(&bar, "IMMEDIATE MODE UI FOR UIKIT", color: theme.textDim)
        }

        if let tapped = tabs(&ctx, Page.allCases.map(\.title), selected: page.rawValue, key: "tabs", in: ctx.cutTop(13, gap: 5)) {
            page = Page(rawValue: tapped) ?? page
        }

        let status = ctx.cutBottom(13, gap: 4)
        let body = ctx.bounds
        let isWide = body.width >= 560

        switch page {
        case .scroll:
            ctx.region(body, key: "page-scroll") { drawScrollPage(&$0, isWide: isWide) }
        default:
            scrollView(&ctx, fade: 10, key: .string("page-\(page.rawValue)"), in: body) { content, _ in
                content.gap = 6
                drawPage(&content, isWide: isWide)
                content.space(6)
            }
        }

        statusLine(&ctx, text: "READY - HOLD ANYTHING FOR A HINT", message: message, serial: messageSerial, in: SZRect(status.x - 6, status.y, status.width + 12, status.height))
        tooltip(&ctx)
    }

    private func drawPage(_ ctx: inout SZContext, isWide: Bool) {
        let columns: [(inout SZContext) -> Void] = switch page {
        case .core: [drawCoreLeft, drawCoreRight]
        case .controls: [drawControlsLeft, drawControlsRight]
        case .text: [drawTextLeft, drawTextRight]
        case .crt: [drawCRTLeft, drawCRTRight]
        case .scroll: []
        }
        if isWide {
            ctx.row(gap: 8) { row in
                let width = (row.bounds.width - 8) / 2
                for draw in columns {
                    row.column(width: width, gap: 6) { draw(&$0) }
                }
            }
        } else {
            for draw in columns {
                draw(&ctx)
            }
        }
    }
}
