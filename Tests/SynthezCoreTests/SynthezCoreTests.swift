//
//  SynthezCoreTests.swift
//  SynthezCoreTests
//

@testable import SynthezCore
import Testing

private func makeUI() -> SZUI {
    SZUI(palette: SZPalette(colors: [
        SZRGBA(hex: 0x000000), SZRGBA(hex: 0x444444), SZRGBA(hex: 0x888888), SZRGBA(hex: 0xFFFFFF),
    ]))
}

private let size = SZSize(100, 80)

@Suite("Layout")
struct LayoutTests {
    @Test func `place flows with gap and alignment`() {
        let ui = makeUI()
        var rects: [SZRect] = []
        ui.frame(time: 0, size: size, events: []) { ctx in
            ctx.gap = 2
            rects.append(ctx.place(width: 10, height: 5))
            rects.append(ctx.place(width: 20, height: 5))
            ctx.align = .center
            rects.append(ctx.place(width: 20, height: 5))
            ctx.align = .stretch
            rects.append(ctx.place(width: 20, height: 5))
        }
        #expect(rects == [SZRect(0, 0, 10, 5), SZRect(0, 7, 20, 5), SZRect(40, 14, 20, 5), SZRect(0, 21, 100, 5)])
    }

    @Test func `row advances by natural size`() {
        let ui = makeUI()
        var after = SZRect.zero
        var inRow: [SZRect] = []
        ui.frame(time: 0, size: size, events: []) { ctx in
            ctx.inset(4)
            ctx.row(gap: 3) { row in
                inRow.append(row.place(width: 10, height: 6))
                inRow.append(row.place(width: 10, height: 9))
            }
            after = ctx.place(width: 5, height: 5)
        }
        #expect(inRow == [SZRect(0, 0, 10, 6), SZRect(13, 0, 10, 9)])
        #expect(after == SZRect(4, 13, 5, 5))
    }

    @Test func `cuts shrink bounds`() {
        let ui = makeUI()
        var rects: [SZRect] = []
        var bounds = SZRect.zero
        ui.frame(time: 0, size: size, events: []) { ctx in
            rects.append(ctx.cutTop(10, gap: 2))
            rects.append(ctx.cutRight(20))
            rects.append(ctx.cutLeft(5, gap: 1))
            bounds = ctx.bounds
            rects.append(ctx.place(width: 4, height: 4))
        }
        #expect(rects == [SZRect(0, 0, 100, 10), SZRect(80, 12, 20, 68), SZRect(0, 12, 5, 68), SZRect(6, 12, 4, 4)])
        #expect(bounds == SZRect(6, 12, 74, 68))
    }
}

@Suite("Identity and state")
struct StateTests {
    @Test func `positional I ds are stable across frames`() {
        let ui = makeUI()
        var ids: [[SZID]] = []
        for i in 0 ..< 2 {
            var frame: [SZID] = []
            ui.frame(time: Double(i), size: size, events: []) { ctx in
                frame.append(ctx.makeKey())
                ctx.row { row in frame.append(row.makeKey()) }
                frame.append(ctx.makeKey())
                frame.append(ctx.makeKey("named"))
            }
            ids.append(frame)
        }
        #expect(ids[0] == ids[1])
        #expect(Set(ids[0]).count == 4)
        #expect(ids[0][3] == SZID("named"))
    }

    @Test func `state lives while visited`() {
        let ui = makeUI()
        func frame(_ show: Bool) -> Int? {
            var value: Int?
            ui.frame(time: 0, size: size, events: []) { ctx in
                guard show else { return }
                let state = ctx.state(key: "counter", 0)
                state.value += 1
                value = state.value
            }
            return value
        }
        #expect(frame(true) == 1)
        #expect(frame(true) == 2)
        #expect(frame(false) == nil)
        #expect(frame(true) == 1)
    }

    @Test func `animated value eases and requests frames`() {
        let ui = makeUI()
        var target = 0.0
        var value = 0.0
        var result = ui.frame(time: 0, size: size, events: []) { ctx in
            value = ctx.animatedValue(target, key: "a")
        }
        #expect(value == 0 && !result.needsAnotherFrame)
        target = 100
        var t = 0.0
        var frames = 0
        repeat {
            t += 1.0 / 60
            frames += 1
            result = ui.frame(time: t, size: size, events: []) { ctx in
                value = ctx.animatedValue(target, key: "a")
            }
        } while result.needsAnotherFrame && frames < 500
        #expect(value == 100)
        #expect(frames > 5 && frames < 100)
    }

    @Test func `animation after idle starts with one frame step`() {
        let ui = makeUI()
        var target = 0.0
        var value = 0.0
        _ = ui.frame(time: 0, size: size, events: []) { ctx in value = ctx.animatedValue(target, key: "a") }
        // Ten idle seconds pass with the display link paused.
        target = 100
        _ = ui.frame(time: 10, size: size, events: []) { ctx in value = ctx.animatedValue(target, key: "a") }
        #expect(abs(value - 15) < 0.01)
        // Once moving, real elapsed time counts.
        _ = ui.frame(time: 10 + 2.0 / 60, size: size, events: []) { ctx in value = ctx.animatedValue(target, key: "a") }
        #expect(value > 35 && value < 40)
    }
}

@Suite("Input routing")
struct InputTests {
    /// Draws a button-like rect and an optional overlay over it.
    private func frame(_ ui: SZUI, _ events: [SZInputEvent], overlay: Bool = false, clip: SZRect? = nil) -> (base: SZInteraction, top: SZInteraction?) {
        var base = SZInteraction(id: .root)
        var top: SZInteraction?
        ui.frame(time: 0, size: size, events: events) { ctx in
            if let clip {
                base = ctx.clip(clip) { c in c.interaction(SZRect(10, 10, 20, 20), key: "base") }
            } else {
                base = ctx.interaction(SZRect(10, 10, 20, 20), key: "base")
            }
            if overlay {
                top = ctx.overlay { o in o.interaction(SZRect(0, 0, 25, 25), key: "top") }
            }
        }
        return (base, top)
    }

    @Test func `tap clicks on release`() {
        let ui = makeUI()
        _ = frame(ui, [])
        let down = frame(ui, [.pointerDown(SZPoint(15, 15), kind: .touch)]).base
        #expect(down.pressed && down.held && down.hovered && !down.clicked)
        let moved = frame(ui, [.pointerMove(SZPoint(18, 19), kind: .touch)]).base
        #expect(moved.held && moved.dx == 3 && moved.dy == 4)
        let up = frame(ui, [.pointerUp(SZPoint(18, 19), kind: .touch)]).base
        #expect(up.released && up.clicked && !up.held)
        let after = frame(ui, []).base
        #expect(!after.hovered && !after.clicked)
    }

    @Test func `release outside does not click`() {
        let ui = makeUI()
        _ = frame(ui, [])
        _ = frame(ui, [.pointerDown(SZPoint(15, 15), kind: .touch)])
        let up = frame(ui, [.pointerUp(SZPoint(60, 60), kind: .touch)]).base
        #expect(up.released && !up.clicked)
    }

    @Test func `overlay blocks lower layer`() {
        let ui = makeUI()
        _ = frame(ui, [], overlay: true)
        let result = frame(ui, [.pointerDown(SZPoint(15, 15), kind: .touch)], overlay: true)
        #expect(result.top?.pressed == true)
        #expect(!result.base.pressed)
        // Outside the overlay the base still answers.
        _ = frame(ui, [.pointerUp(SZPoint(15, 15), kind: .touch)], overlay: true)
        let outside = frame(ui, [.pointerDown(SZPoint(28, 28), kind: .touch)], overlay: true)
        #expect(outside.base.pressed)
    }

    @Test func `clipped part does not hit`() {
        let ui = makeUI()
        let clip = SZRect(0, 0, 20, 100)
        _ = frame(ui, [], clip: clip)
        #expect(!frame(ui, [.pointerDown(SZPoint(25, 15), kind: .touch)], clip: clip).base.pressed)
        _ = frame(ui, [.pointerUp(SZPoint(25, 15), kind: .touch)], clip: clip)
        #expect(frame(ui, [.pointerDown(SZPoint(15, 15), kind: .touch)], clip: clip).base.pressed)
    }

    @Test func `double tap counts presses`() {
        let ui = makeUI()
        _ = frame(ui, [])
        // A whole tap in one batch: the press shows this frame, the release next.
        let down = frame(ui, [.pointerDown(SZPoint(15, 15), kind: .touch), .pointerUp(SZPoint(15, 15), kind: .touch)]).base
        #expect(down.pressed && down.held && !down.clicked)
        #expect(ui.hasDeferredInput)
        let first = frame(ui, []).base
        #expect(first.clicked && first.presses == 1)
        let second = frame(ui, [.pointerDown(SZPoint(16, 15), kind: .touch)]).base
        #expect(second.doubleClicked)
    }
}

@Suite("Raster and draw list")
struct RasterTests {
    @Test func `fill honors pattern and clip`() {
        let surface = SZSurface(width: 8, height: 8)
        surface.fill(SZRect(-2, -2, 20, 20), color: 3, pattern: SZPatterns.half, clip: SZRect(0, 0, 4, 4))
        var lit = 0
        for y in 0 ..< 8 {
            for x in 0 ..< 8 where surface[x, y] == 3 {
                lit += 1
                #expect(x < 4 && y < 4)
                #expect(SZPatterns.covers(SZPatterns.half, x, y))
            }
        }
        #expect(lit == 8)
    }

    @Test func `dither levels nest`() {
        for level in 0 ..< 16 {
            let a = SZPatterns.dither(level), b = SZPatterns.dither(level + 1)
            #expect(a & b == a)
            #expect(b.nonzeroBitCount == level + 1)
        }
    }

    @Test func `text blits glyphs`() {
        let font = SZBitmapFont(name: "t", glyphs: [("A", SZBitmap(["#.", ".#"])), ("?", SZBitmap(["##"]))])
        let list = SZDrawList()
        list.begin(screen: SZRect(0, 0, 6, 2), background: 0)
        let width = list.appendText("AA", font: font, at: .zero, color: 2, scale: 1, clip: 0, layer: 0)
        #expect(width == 5)
        let surface = SZSurface(width: 6, height: 2)
        surface.render(list)
        #expect(surface.pixels == [2, 0, 0, 2, 0, 0, 0, 2, 0, 0, 2, 0])
    }

    @Test func `overlay layer draws on top`() {
        let ui = makeUI()
        ui.frame(time: 0, size: SZSize(4, 1), events: []) { ctx in
            ctx.overlay { o in o.fill(SZRect(0, 0, 2, 1), color: 3) }
            ctx.fill(SZRect(0, 0, 4, 1), color: 2)
        }
        let surface = SZSurface(width: 4, height: 1)
        surface.render(ui.drawList)
        #expect(surface.pixels == [3, 3, 2, 2])
    }

    @Test func `identical frames are unchanged`() {
        let ui = makeUI()
        let font = SZBitmapFont(name: "t", glyphs: [("?", SZBitmap(["#"]))])
        var text = "ab"
        func frame() -> SZFrameResult {
            ui.frame(time: 0, size: size, events: []) { ctx in
                ctx.fill(SZRect(0, 0, 10, 10), color: 1)
                ctx.text(text, at: SZPoint(2, 2), font: font, color: 3)
            }
        }
        #expect(frame().changed)
        #expect(!frame().changed)
        text = "abc"
        #expect(frame().changed)
        #expect(!frame().changed)
    }

    @Test func `offscreen drawing is culled`() {
        let ui = makeUI()
        ui.frame(time: 0, size: size, events: []) { ctx in
            ctx.fill(SZRect(200, 0, 10, 10), color: 1)
            ctx.clip(SZRect(0, 0, 10, 10)) { c in c.fill(SZRect(20, 20, 5, 5), color: 1) }
        }
        #expect(ui.drawList.commandCount == 0)
    }
}

@Suite("Palette and scheduling")
struct PaletteTests {
    @Test func `mix map moves toward target`() {
        let palette = SZPalette(colors: [SZRGBA(hex: 0x000000), SZRGBA(hex: 0x555555), SZRGBA(hex: 0xAAAAAA), SZRGBA(hex: 0xFFFFFF)])
        let full = palette.mixMap(toward: 0, amount: 1)
        #expect(full.table[0 ..< 4] == [0, 0, 0, 0])
        let none = palette.mixMap(toward: 0, amount: 0)
        #expect(none.table[0 ..< 4] == [0, 1, 2, 3])
        #expect(palette.mixMap(toward: 0, amount: 1) === full)
    }

    @Test func `scheduler idles until invalidated`() {
        var scheduler = SZFrameScheduler()
        #expect(scheduler.isDue(at: 0, hasInput: false))
        let keepsTicking = scheduler.didDraw(at: 0, result: SZFrameResult(needsAnotherFrame: false, changed: true))
        #expect(!keepsTicking)
        #expect(!scheduler.isDue(at: 1, hasInput: false))
        #expect(scheduler.isDue(at: 1, hasInput: true))
        scheduler.invalidate()
        #expect(scheduler.isDue(at: 1, hasInput: false))
    }

    @Test func `scheduler settles after change`() {
        var scheduler = SZFrameScheduler(settleDuration: 0.5)
        let keepsTicking = scheduler.didDraw(at: 0, result: SZFrameResult(needsAnotherFrame: false, changed: true))
        #expect(keepsTicking)
        #expect(scheduler.isDue(at: 0.4, hasInput: false))
        #expect(!scheduler.isDue(at: 0.6, hasInput: false))
    }

    @Test func `screen letterboxes`() {
        let screen = SZScreen(resolution: .fixed(width: 640, height: 400), deviceWidth: 1600, deviceHeight: 1200)
        #expect(screen.scale == 2.5)
        #expect(screen.viewportY == 100)
        #expect(screen.virtualPoint(deviceX: 5, deviceY: 102.5) == SZPoint(2, 1))
    }
}
