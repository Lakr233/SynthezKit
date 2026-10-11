//
//  main.swift
//  SynthezBench
//
//  Headless baseline: builds the gallery frame and rasterizes it, timing
//  each stage. Run with `swift run -c release SynthezBench`.
//

import CoreGraphics
import Foundation
import ImageIO
import SynthezCore
import SynthezGallery
import SynthezWidgets

struct Stats {
    var samples: [Double] = []

    mutating func add(_ seconds: Double) {
        samples.append(seconds * 1e6)
    }

    func line(_ name: String) -> String {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return name }
        func pct(_ p: Double) -> Double {
            sorted[min(Int(Double(sorted.count - 1) * p), sorted.count - 1)]
        }
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        let label = name.padding(toLength: 26, withPad: " ", startingAt: 0)
        return label + String(format: "mean %8.1f  p50 %8.1f  p95 %8.1f  p99 %8.1f  µs", mean, pct(0.5), pct(0.95), pct(0.99))
    }
}

func now() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1e9
}

func run(name: String, page: SZGallery.Page, gridCount: Int, frames: Int, interactive: Bool) {
    let palette = SZTheme.synthPalette()
    let ui = SZUI(palette: palette, background: 1)
    let gallery = SZGallery(gridCount: gridCount)
    gallery.page = page
    let screen = SZScreen(resolution: SZGallery.resolution, deviceWidth: 2556, deviceHeight: 1179)
    let surface = SZSurface(width: screen.size.width, height: screen.size.height)

    var build = Stats(), raster = Stats(), total = Stats()
    var changedFrames = 0
    var commands = 0
    let warmup = 60
    for i in 0 ..< (frames + warmup) {
        var events: [SZInputEvent] = []
        if interactive {
            // Sweep a pressed pointer across the pads and sliders.
            let x = 320 + (i * 7) % 300
            let y = 60 + (i * 3) % 300
            switch i % 4 {
            case 0: events.append(.pointerDown(SZPoint(x, y), kind: .touch))
            case 1, 2: events.append(.pointerMove(SZPoint(x + 4, y + 2), kind: .touch))
            default: events.append(.pointerUp(SZPoint(x + 4, y + 2), kind: .touch))
            }
        }
        let t0 = now()
        let result = ui.frame(time: Double(i) / 120, size: screen.size, events: events) { ctx in
            gallery.draw(&ctx)
        }
        let t1 = now()
        if result.changed {
            surface.render(ui.drawList)
        }
        let t2 = now()
        guard i >= warmup else { continue }
        build.add(t1 - t0)
        if result.changed {
            raster.add(t2 - t1)
            changedFrames += 1
        }
        total.add(t2 - t0)
        commands = ui.drawList.commandCount
    }
    print("== \(name): \(frames) frames, grid \(gridCount), \(commands) commands, \(changedFrames) rasterized")
    print(build.line("ui build + draw list"))
    print(raster.line("raster (changed frames)"))
    print(total.line("total"))
}

/// Writes every page, settled, as PNGs at 2× nearest-neighbour, for
/// checking layouts without a device: `SynthezBench --snapshot <dir>`.
func snapshot(to directory: String) {
    for size in [SZSize(640, 400), SZSize(402, 778)] {
        for page in SZGallery.Page.allCases {
            let ui = SZUI(palette: SZTheme.synthPalette(), background: 1)
            let gallery = SZGallery()
            gallery.page = page
            for i in 0 ..< 120 {
                ui.frame(time: Double(i) / 60, size: size, events: []) { gallery.draw(&$0) }
            }
            let surface = SZSurface(width: size.width, height: size.height)
            surface.render(ui.drawList)
            let scale = 2
            var rgba = [UInt8](repeating: 255, count: size.width * scale * size.height * scale * 4)
            for y in 0 ..< size.height * scale {
                for x in 0 ..< size.width * scale {
                    let c = ui.palette.colors[Int(surface[x / scale, y / scale])]
                    let o = (y * size.width * scale + x) * 4
                    rgba[o] = c.r; rgba[o + 1] = c.g; rgba[o + 2] = c.b
                }
            }
            let provider = CGDataProvider(data: Data(rgba) as CFData)!
            let image = CGImage(width: size.width * scale, height: size.height * scale, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size.width * scale * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(page)-\(size.width)x\(size.height).png")
            let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
            print("wrote", url.path)
        }
    }
}

if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--snapshot" {
    snapshot(to: CommandLine.arguments[2])
    exit(0)
}

let frames = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 2000
print("SynthezBench, virtual 640x400")
for page in SZGallery.Page.allCases {
    run(name: "\(page) idle", page: page, gridCount: 24, frames: frames, interactive: false)
    run(name: "\(page) interactive", page: page, gridCount: 24, frames: frames, interactive: true)
}

run(name: "controls, 640 pads", page: .controls, gridCount: 640, frames: frames, interactive: true)
