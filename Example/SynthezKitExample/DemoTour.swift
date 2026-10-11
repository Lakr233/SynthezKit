//
//  DemoTour.swift
//  SynthezKitExample
//
//  A scripted walk through every page, for recording the gallery: launch
//  with `-SZDemoTour YES`. It finds widgets by their accessibility labels
//  and sends the canvas the same events a finger would.
//

import SynthezKit

@MainActor
final class DemoTour {
    enum Step {
        case tap(String, index: Int = 0)
        case drag(String, index: Int = 0, dx: Int, dy: Int, duration: Double = 0.6)
        case swipe(from: SZPoint, to: SZPoint, duration: Double)
        case text(String)
        case key(SZKeyCode)
        case wait(Double)
    }

    private weak var canvas: SZCanvasView?

    init(canvas: SZCanvasView) {
        self.canvas = canvas
    }

    static let steps: [Step] = [
        .wait(1.0),
        // Core.
        .tap("+"), .wait(0.3), .tap("+"), .wait(0.4),
        .tap("SAW"), .wait(0.8), .tap("NOISE"), .wait(0.8),
        .tap("PLAY"), .wait(2.0), .tap("PAUSE"), .wait(0.3),
        .tap("ANIMATE STRENGTH"), .wait(2.5), .tap("ANIMATE STRENGTH"), .wait(0.4),
        .tap("SWAP"), .wait(0.6),
        .drag("RIDE", dx: -180, dy: 0, duration: 0.35), .wait(1.2),
        .tap("OPEN THE SHEET"), .wait(1.2),
        .tap("STAR COLD STEEL"), .wait(0.6), .tap("AMBER TUBE"), .wait(1.2),
        .tap("MENU"), .wait(1.0), .tap("REDO"), .wait(1.0),
        // Controls.
        .tap("CONTROLS"), .wait(0.8),
        .tap("TECHNO"), .wait(0.3), .tap("DRONE"), .wait(0.3), .tap("MUTE"), .wait(0.3),
        .tap("1/16"), .wait(0.6), .tap("NEXT"), .wait(0.5), .tap("NEXT", index: 1), .wait(0.5),
        .drag("BPM", dx: 50, dy: 0), .wait(0.5),
        .tap("LOWPASS"), .wait(0.9), .tap("BANDPASS"), .wait(0.8),
        .drag("CUTOFF", dx: 0, dy: -35), .wait(0.4),
        .drag("DRIVE", dx: 0, dy: 30), .wait(0.4),
        .drag("CUTOFF", index: 1, dx: 90, dy: 0), .wait(0.4),
        .drag("LOW", dx: 0, dy: -22), .wait(0.3), .drag("AIR", dx: 0, dy: 26), .wait(0.6),
        // Text.
        .tap("TEXT"), .wait(0.8),
        .tap("TITLE"), .wait(0.8), .text(" MIX"), .wait(0.6), .key(.enter), .wait(0.8),
        .tap("DIGITS"), .wait(0.6), .key(.backspace), .key(.backspace), .text("9X7"), .wait(0.5), .key(.enter), .wait(0.8),
        .tap("CENTER"), .wait(0.8), .tap("RIGHT"), .wait(0.8),
        // Scroll.
        .tap("SCROLL"), .wait(0.8),
        .swipe(from: SZPoint(200, 300), to: SZPoint(200, 120), duration: 0.12), .wait(2.4),
        .swipe(from: SZPoint(200, 120), to: SZPoint(200, 320), duration: 0.4), .wait(1.6),
        .tap("ROW 3"), .wait(0.6),
        .swipe(from: SZPoint(330, 392), to: SZPoint(150, 392), duration: 0.3), .wait(1.4),
        .drag("CHANNEL 7", dx: 0, dy: -30), .wait(0.8),
        // CRT.
        .tap("CRT", index: 1), .wait(0.8),
        .tap("ENABLED"), .wait(1.5),
        .drag("AFTERGLOW", dx: 140, dy: 0), .wait(2.5),
        .tap("SLOT"), .wait(1.2), .tap("SHADOW"), .wait(1.2),
        .drag("HALATION", dx: 120, dy: 0), .wait(2.0),
        .tap("DEFAULTS"), .wait(1.0), .tap("ENABLED"), .wait(1.0),
        .tap("CORE"), .wait(1.5),
    ]

    func run() {
        Task { @MainActor in
            for step in Self.steps {
                await perform(step)
            }
        }
    }

    private func perform(_ step: Step) async {
        guard let canvas else { return }
        switch step {
        case let .tap(label, index):
            guard let center = center(of: label, index: index) else { return }
            canvas.send(.pointerDown(center, kind: .touch))
            await pause(0.08)
            canvas.send(.pointerUp(center, kind: .touch))
        case let .drag(label, index, dx, dy, duration):
            guard let center = center(of: label, index: index) else { return }
            await stroke(from: center, to: SZPoint(center.x + dx, center.y + dy), duration: duration)
        case let .swipe(from, to, duration):
            await stroke(from: from, to: to, duration: duration)
        case let .text(text):
            canvas.send(.text(text))
        case let .key(code):
            canvas.send(.key(code, modifiers: []))
        case let .wait(seconds):
            await pause(seconds)
        }
    }

    /// A finger moving in a straight line at 60 Hz.
    private func stroke(from: SZPoint, to: SZPoint, duration: Double) async {
        guard let canvas else { return }
        canvas.send(.pointerDown(from, kind: .touch))
        let steps = max(Int(duration * 60), 2)
        for i in 1 ... steps {
            await pause(duration / Double(steps))
            let t = Double(i) / Double(steps)
            let p = SZPoint(from.x + Int(Double(to.x - from.x) * t), from.y + Int(Double(to.y - from.y) * t))
            canvas.send(.pointerMove(p, kind: .touch))
        }
        canvas.send(.pointerUp(to, kind: .touch))
    }

    private func center(of label: String, index: Int) -> SZPoint? {
        let matches = canvas?.ui.accessibilityItems.filter { $0.label == label } ?? []
        guard matches.indices.contains(index) else { return nil }
        let r = matches[index].rect
        return SZPoint(r.x + r.width / 2, r.y + r.height / 2)
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
