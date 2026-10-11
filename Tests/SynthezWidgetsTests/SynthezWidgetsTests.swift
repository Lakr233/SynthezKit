//
//  SynthezWidgetsTests.swift
//  SynthezWidgetsTests
//

import SynthezCore
import SynthezGallery
import SynthezWidgets
import Testing

@Suite("Widgets")
struct WidgetsTests {
    @Test func `pixel font covers printable ASCII`() {
        let font = SZBitmapFont.pixel5x7()
        let fallback = font.glyphIndex(for: UInt32(UInt8(ascii: "?")))
        for scalar in UInt32(0x20) ... 0x7E where scalar != UInt32(UInt8(ascii: "?")) {
            #expect(font.glyphIndex(for: scalar) != fallback, "missing \(Character(Unicode.Scalar(scalar)!))")
        }
        #expect(font.glyphs.allSatisfy { $0.height == 7 })
        #expect(font.measure("AB") == 11)
    }

    @Test func `button clicks across frames`() {
        let ui = SZUI(palette: SZTheme.synthPalette())
        var clicks = 0
        func frame(_ events: [SZInputEvent]) {
            ui.frame(time: 0, size: SZSize(100, 50), events: events) { ctx in
                if button(&ctx, "GO", in: SZRect(10, 10, 30, 11)).clicked {
                    clicks += 1
                }
            }
        }
        frame([])
        frame([.pointerDown(SZPoint(20, 15), kind: .touch)])
        frame([.pointerUp(SZPoint(20, 15), kind: .touch)])
        #expect(clicks == 1)
    }

    @Test func `segmented glides and settles`() {
        let ui = SZUI(palette: SZTheme.synthPalette())
        var selected = 0
        var frames = 0
        func frame(_ t: Double, _ events: [SZInputEvent] = []) -> SZFrameResult {
            ui.frame(time: t, size: SZSize(200, 50), events: events) { ctx in
                if let picked = segmented(&ctx, ["A", "B", "C", "D"], selected: selected, in: SZRect(0, 0, 162, 13)) {
                    selected = picked
                }
            }
        }
        _ = frame(0)
        _ = frame(0.01, [.pointerDown(SZPoint(130, 5), kind: .touch), .pointerUp(SZPoint(130, 5), kind: .touch)])
        _ = frame(0.015)
        #expect(selected == 3)
        var t = 0.02
        while frame(t).needsAnotherFrame, frames < 200 {
            t += 1.0 / 120
            frames += 1
        }
        #expect(frames > 3 && frames < 200)
    }

    @Test func `gallery is stable when idle`() throws {
        let ui = SZUI(palette: SZTheme.synthPalette())
        let gallery = SZGallery()
        var results: [SZFrameResult] = []
        for i in 0 ..< 60 {
            results.append(ui.frame(time: Double(i) / 60, size: SZSize(640, 400), events: []) { gallery.draw(&$0) })
        }
        // Cards measure their content on the first frame, then settle.
        #expect(try !(#require(results.last?.changed)))
        #expect(try !(#require(results.last?.needsAnotherFrame)))
        #expect(ui.drawList.commandCount > 100)
    }

    @Test(arguments: SZGallery.Page.allCases)
    func `every page builds and settles`(page: SZGallery.Page) {
        let ui = SZUI(palette: SZTheme.synthPalette())
        let gallery = SZGallery()
        gallery.page = page
        var last = SZFrameResult(needsAnotherFrame: true, changed: true)
        for size in [SZSize(402, 790), SZSize(640, 400)] {
            for i in 0 ..< 90 {
                last = ui.frame(time: Double(i) / 60, size: size, events: []) { gallery.draw(&$0) }
            }
            #expect(ui.drawList.commandCount > 50)
            #expect(ui.accessibilityItems.count > 5)
        }
        // The CRT page sweeps a bar forever; the others come to rest.
        #expect(last.needsAnotherFrame == (page == .crt))
    }

    @Test func `state changed by input is drawn next frame`() {
        let ui = SZUI(palette: SZTheme.synthPalette())
        var on = false
        var t = 0.0
        func frame(_ events: [SZInputEvent]) -> SZFrameResult {
            t += 1.0 / 60
            return ui.frame(time: t, size: SZSize(100, 40), events: events) { ctx in
                if button(&ctx, "X", on: on, in: SZRect(0, 0, 20, 11)).clicked {
                    on.toggle()
                }
            }
        }
        _ = frame([])
        _ = frame([.pointerDown(SZPoint(5, 5), kind: .touch)])
        let tap = frame([.pointerUp(SZPoint(5, 5), kind: .touch)])
        #expect(on)
        // The tap frame drew the button off; it must ask for the frame that draws it on.
        #expect(tap.needsAnotherFrame)
        #expect(frame([]).changed)
    }

    @Test func `deferred release still asks for the next frame`() {
        let ui = SZUI(palette: SZTheme.synthPalette())
        var on = false
        var t = 0.0
        func frame(_ events: [SZInputEvent]) -> SZFrameResult {
            t += 1.0 / 60
            return ui.frame(time: t, size: SZSize(100, 40), events: events) { ctx in
                if button(&ctx, "X", on: on, in: SZRect(0, 0, 20, 11)).clicked {
                    on.toggle()
                }
            }
        }
        _ = frame([])
        // A whole tap in one batch: the release is applied a frame later,
        // from the deferred queue, and its click must still be drawn.
        _ = frame([.pointerDown(SZPoint(5, 5), kind: .touch), .pointerUp(SZPoint(5, 5), kind: .touch)])
        let release = frame([])
        #expect(on)
        #expect(release.needsAnotherFrame)
        #expect(frame([]).changed)
    }

    @Test func `scroll view flings and settles`() {
        let ui = SZUI(palette: SZTheme.synthPalette())
        var offset = SZPoint.zero
        var t = 0.0
        func frame(_ events: [SZInputEvent]) -> SZFrameResult {
            t += 1.0 / 60
            return ui.frame(time: t, size: SZSize(100, 100), events: events) { ctx in
                scrollView(&ctx, content: SZSize(100, 1000), in: SZRect(0, 0, 100, 100)) { c, scroll in
                    offset = scroll.offset
                    for i in 0 ..< 50 {
                        button(&c, "B\(i)", key: .int(i), in: SZRect(0, i * 20, 80, 11))
                    }
                }
            }
        }
        _ = frame([])
        _ = frame([.pointerDown(SZPoint(40, 80), kind: .touch)])
        for y in stride(from: 70, through: 20, by: -10) {
            _ = frame([.pointerMove(SZPoint(40, y), kind: .touch)])
        }
        #expect(offset.y > 40)
        _ = frame([.pointerUp(SZPoint(40, 20), kind: .touch)])
        let released = offset.y
        var frames = 0
        while frame([]).needsAnotherFrame, frames < 600 {
            frames += 1
        }
        #expect(offset.y > released + 20)
        #expect(offset.y <= 900)
        #expect(frames < 600)
    }

    @Test func `drag inside one frame still scrolls`() {
        let ui = SZUI(palette: SZTheme.synthPalette())
        var offset = SZPoint.zero
        var t = 0.0
        func frame(_ events: [SZInputEvent]) -> SZFrameResult {
            t += 1.0 / 60
            return ui.frame(time: t, size: SZSize(100, 100), events: events) { ctx in
                scrollView(&ctx, content: SZSize(100, 1000), in: SZRect(0, 0, 100, 100)) { c, scroll in
                    offset = scroll.offset
                    for i in 0 ..< 50 {
                        button(&c, "B\(i)", key: .int(i), in: SZRect(0, i * 20, 80, 11))
                    }
                }
            }
        }
        _ = frame([])
        // A hitch: the whole drag arrives between two frames.
        var events: [SZInputEvent] = [.pointerDown(SZPoint(40, 90), kind: .touch)]
        for y in stride(from: 80, through: 30, by: -10) {
            events.append(.pointerMove(SZPoint(40, y), kind: .touch))
        }
        events.append(.pointerUp(SZPoint(40, 30), kind: .touch))
        var frames = 0
        var result = frame(events)
        while result.needsAnotherFrame, frames < 300 {
            result = frame([])
            frames += 1
        }
        #expect(offset.y >= 50)
    }

    @Test func `text field types and commits`() {
        let ui = SZUI(palette: SZTheme.synthPalette())
        var value = "AB"
        var request: SZTextInputRequest?
        func frame(_ events: [SZInputEvent]) {
            let result = ui.frame(time: 0, size: SZSize(200, 50), events: events) { ctx in
                let r = textField(&ctx, value: value, maxLength: 4, in: SZRect(0, 0, 100, 13))
                if r.committed {
                    value = r.text
                }
            }
            request = result.textInput
        }
        frame([])
        frame([.pointerDown(SZPoint(50, 5), kind: .touch), .pointerUp(SZPoint(50, 5), kind: .touch)])
        #expect(request != nil)
        frame([.text("CDEF"), .key(.backspace, modifiers: []), .text("Z")])
        frame([.key(.enter, modifiers: [])])
        #expect(value == "ABCZ")
        frame([])
        #expect(request == nil)
    }
}
