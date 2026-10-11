//
//  Gallery+CRT.swift
//  SynthezGallery
//

import Foundation
import SynthezCore
import SynthezWidgets

extension SZGallery {
    func drawCRTLeft(_ ctx: inout SZContext) {
        let theme = ctx.theme
        card(&ctx, "CRT - PHYSICAL MODEL") { c in
            c.gap = 4
            c.row(height: 11, gap: 6, align: .center) { row in
                if checkbox(&row, "ENABLED", checked: crt.isEnabled, hint: "RUN THE CRT PIPELINE").clicked {
                    crt.isEnabled.toggle()
                }
                if button(&row, "DEFAULTS", hint: "RESTORE EVERY PARAMETER").clicked {
                    let enabled = crt.isEnabled
                    crt = SZCRTSettings()
                    crt.isEnabled = enabled
                    post("CRT DEFAULTS")
                }
            }
            if let i = segmented(&c, ["FLAT", "APERTURE", "SLOT", "SHADOW"], selected: crt.mask.rawValue, key: "mask") {
                crt.mask = SZCRTMask(rawValue: i) ?? .aperture
            }
            func parameter(_ name: String, _ value: Double, _ range: ClosedRange<Double>, step: Double? = nil, _ format: String = "%.2f", set: (Double) -> Void) {
                c.row(height: 9, gap: 6, align: .center) { row in
                    label(&row, name, color: theme.textDim, in: row.place(width: 56, height: 9))
                    if let v = slider(&row, value: value, range: range, step: step, length: row.bounds.width - row.cursor.x - 34, label: name, key: .string("crt-\(name)")) {
                        set(v)
                    }
                    label(&row, String(format: format, value), color: theme.text)
                }
            }
            parameter("SCANLINES", crt.scanlines, 0 ... 1) { crt.scanlines = $0 }
            parameter("BEAM DIM", crt.beamDim, 0.1 ... 0.6) { crt.beamDim = $0 }
            parameter("BEAM HOT", crt.beamBright, 0.2 ... 0.9) { crt.beamBright = $0 }
            parameter("MASK", crt.maskStrength, 0 ... 1) { crt.maskStrength = $0 }
            parameter("HALATION", crt.halation, 0 ... 1) { crt.halation = $0 }
            parameter("SPREAD", Double(crt.spread), 1 ... 6, step: 1, "%.0f") { crt.spread = Int($0) }
            parameter("VIGNETTE", crt.vignette, 0 ... 1) { crt.vignette = $0 }
            parameter("AFTERGLOW", crt.persistence, 0 ... 0.3, "%.2f") { crt.persistence = $0 }
            parameter("BRIGHTNESS", crt.brightness, 0.6 ... 2) { crt.brightness = $0 }
        }
    }

    func drawCRTRight(_ ctx: inout SZContext) {
        let theme = ctx.theme
        card(&ctx, "TEST PATTERN") { c in
            c.gap = 4
            // Every grey of the palette, then the accents.
            let ramp = c.place(SZSize(0, 12))
            let greys = 14
            for i in 0 ..< greys {
                let x0 = ramp.x + ramp.width * i / greys, x1 = ramp.x + ramp.width * (i + 1) / greys
                c.fill(SZRect(x0, ramp.y, x1 - x0, ramp.height), color: SZColor(i))
            }
            let accents = c.place(SZSize(0, 12))
            for i in 0 ..< 4 {
                let x0 = accents.x + accents.width * i / 4, x1 = accents.x + accents.width * (i + 1) / 4
                c.fill(SZRect(x0, accents.y, x1 - x0, accents.height), color: SZColor(14 + i))
            }
            c.row(height: 7, gap: 6) { row in
                for color in [theme.textDim, theme.text, theme.paper, theme.accent, theme.accentBright] {
                    label(&row, "TEXT", color: color)
                }
            }
            // Fine lines, a white block, a circle and a sweeping bar for the afterglow.
            let field = c.place(SZSize(0, 44))
            c.fill(field, color: SZColor(0))
            for i in 0 ..< 6 {
                c.fill(SZRect(field.x + 4 + i * 4, field.y + 4, 1, 36), color: theme.paper)
                c.fill(SZRect(field.x + 30, field.y + 4 + i * 4, 26, 1), color: theme.paper)
            }
            c.fill(SZRect(field.x + 62, field.y + 6, 20, 20), color: theme.paper)
            c.circle(center: SZPoint(field.x + 104, field.y + 22), radius: 16, color: theme.accent, filled: false)
            c.circle(center: SZPoint(field.x + 104, field.y + 22), radius: 6, color: theme.accentBright)
            let sweep = field.x + 130 + Int(((sin(c.time * 2.4) + 1) / 2 * Double(max(field.width - 140, 1))).rounded())
            c.fill(SZRect(sweep, field.y + 2, 6, field.height - 4), color: theme.paper)
            c.requestFrame()
        }
    }
}
