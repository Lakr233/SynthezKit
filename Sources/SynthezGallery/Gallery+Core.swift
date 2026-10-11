//
//  Gallery+Core.swift
//  SynthezGallery
//

import Foundation
import SynthezCore
import SynthezWidgets

/// A counter that keeps its count in UI state: by call position, or by key.
private func counter(_ ctx: inout SZContext, key: SZKey?) {
    let theme = ctx.theme
    let count = ctx.state(key: key, 0)
    ctx.row(height: 11, gap: 2, align: .center) { row in
        if iconButton(&row, SZIcons.minus, label: "DECREMENT", size: 11).clicked {
            count.value -= 1
        }
        let text = String(format: "%02d", count.value)
        label(&row, text, color: key == nil ? theme.text : theme.accentBright, in: row.place(width: 14, height: 11))
        if iconButton(&row, SZIcons.plus, label: "INCREMENT", size: 11).clicked {
            count.value += 1
        }
    }
}

extension SZGallery {
    func drawCoreLeft(_ ctx: inout SZContext) {
        let theme = ctx.theme
        card(&ctx, "FLOW - NATURAL SIZES IN A ROW") { c in
            c.gap = 5
            c.row(height: 11, gap: 3, align: .center) { row in
                if button(&row, "-", hint: "ONE LESS").clicked {
                    count -= 1
                }
                label(&row, String(count), color: theme.paper, in: row.place(width: 16, height: 11))
                if button(&row, "+", hint: "ONE MORE").clicked {
                    count += 1
                }
                if button(&row, "RESET", disabled: count == 0, hint: "BACK TO ZERO").clicked {
                    count = 0
                    post("COUNTER RESET")
                }
                if button(&row, "LOOP", on: loop, hint: "A BUTTON THAT STAYS ON").clicked {
                    loop.toggle()
                }
            }
            paragraph(&c, "EACH CONTROL ASKS ITS ROW FOR ITS NATURAL SIZE; THE ROW GROWS TO FIT.", color: theme.textDim)
        }

        card(&ctx, "STATE - PER CALL SITE OR BY KEY") { c in
            c.gap = 4
            let names = swapped ? ["RIGHT", "LEFT"] : ["LEFT", "RIGHT"]
            for name in names {
                c.row(height: 11, gap: 6, align: .center) { row in
                    label(&row, name, color: theme.textDim, in: row.place(width: 34, height: 11))
                    counter(&row, key: nil)
                    row.space(6)
                    counter(&row, key: .string("counter:\(name)"))
                }
            }
            c.row(height: 11, gap: 6, align: .center) { row in
                if button(&row, "SWAP", on: swapped, hint: "KEYED COUNTS FOLLOW THEIR ROW").clicked {
                    swapped.toggle()
                }
                label(&row, "POSITION / KEY", color: theme.textDim)
            }
        }

        card(&ctx, "CUTS - SLICE OFF THE EDGES") { c in
            c.gap = 4
            c.region(c.place(SZSize(0, 11))) { bar in
                if button(&bar, "DELETE", disabled: true, in: bar.cutRight(38, gap: 3)).clicked {}
                if button(&bar, "COPY", hint: "DUPLICATE THE TRACK", in: bar.cutRight(30, gap: 3)).clicked {
                    post("TRACK COPIED")
                }
                if button(&bar, "NEW", hint: "ADD A TRACK", in: bar.cutRight(26, gap: 6)).clicked {
                    post("TRACK ADDED")
                }
                label(&bar, "TRACKS 05/16", color: theme.text, in: bar.bounds)
            }
            paragraph(&c, "BUTTONS CUT FROM THE RIGHT; THE LABEL GETS WHAT IS LEFT.", color: theme.textDim)
        }

        card(&ctx, "FILTERS - READS WHAT IS DRAWN") { c in
            c.gap = 4
            if checkbox(&c, "ANIMATE STRENGTH", checked: animateFilters, hint: "SWEEP THE FILTERS OVER TIME").clicked {
                animateFilters.toggle()
            }
            let strength = animateFilters ? 0.5 + 0.5 * sin(c.time * 2) : 1
            if animateFilters {
                c.requestFrame()
            }
            c.row(height: 34, gap: 4) { row in
                let width = (row.bounds.width - 12) / 4
                let names = ["DITHER", "STEPS", "RADIAL", "MOSAIC"]
                for (i, name) in names.enumerated() {
                    let r = row.place(SZSize(width, 34))
                    let swatch = SZRect(r.x, r.y, r.width, 24)
                    row.fill(swatch, color: theme.accent)
                    row.text("SYNTH", at: SZPoint(swatch.x + 3, swatch.y + 5), font: theme.font, color: theme.paper, scale: 2)
                    switch i {
                    case 0:
                        row.filter(swatch, field: row.ramp(swatch, toward: .right, strength: strength), toward: theme.background, blend: .dither)
                    case 1:
                        row.filter(swatch, field: row.ramp(swatch, toward: .right, strength: strength), toward: theme.background, blend: .steps)
                    case 2:
                        let center = SZPoint(swatch.x + swatch.width / 2, swatch.y + swatch.height / 2)
                        row.filter(swatch, field: .radial(center: center, inner: 4, outer: Double(swatch.width) / 2, start: 0, end: strength), toward: theme.background)
                    default:
                        row.mosaic(swatch, size: max(Int((strength * 4).rounded()), 1))
                    }
                    row.text(name, at: SZPoint(r.x, r.y + 27), font: theme.font, color: theme.textDim)
                }
            }
        }
    }

    func drawCoreRight(_ ctx: inout SZContext) {
        let theme = ctx.theme
        card(&ctx, "ANIMATION - A GLIDING LIGHT") { c in
            c.gap = 5
            let waves: [SZOption] = [
                SZOption("SINE", icon: SZIcons.sine, hint: "A PURE TONE"),
                SZOption("SAW", icon: SZIcons.saw, hint: "BRIGHT AND BUZZY"),
                SZOption("SQUARE", icon: SZIcons.square, hint: "HOLLOW, LIKE A CLARINET"),
                SZOption("NOISE", icon: SZIcons.noise, hint: "EVERY FREQUENCY AT ONCE"),
            ]
            if let picked = segmented(&c, waves.map { SZOption($0.label, hint: $0.hint) }, selected: waveform, key: "wave-names") {
                waveform = picked
            }
            // The scope morphs between waveforms and scrolls while playing.
            let scope = c.place(SZSize(0, 30))
            c.fill(scope, color: theme.background)
            c.stroke(scope, color: theme.line)
            c.fill(SZRect(scope.x + 1, scope.y + scope.height / 2, scope.width - 2, 1), color: theme.line, pattern: SZPatterns.half)
            let morph = c.animatedValue(Double(waveform), key: "morph", easing: 0.18, snap: 0.01)
            let phase = playing ? c.time * 1.5 : 0
            if playing {
                c.requestFrame()
            }
            func sample(_ wave: Int, _ t: Double) -> Double {
                let x = t - floor(t)
                switch wave {
                case 0: return sin(x * 2 * .pi)
                case 1: return 2 * x - 1
                case 2: return x < 0.5 ? 1 : -1
                default:
                    let n = sin(floor(t * 24) * 12.9898) * 43758.5453
                    return (n - floor(n)) * 2 - 1
                }
            }
            var previous: SZPoint?
            let amplitude = Double(scope.height / 2 - 3)
            for x in 0 ..< scope.width - 2 {
                let t = Double(x) / Double(scope.width - 2) * 2 + phase
                let lower = Int(floor(morph)), upper = min(lower + 1, 3), f = morph - floor(morph)
                let v = sample(lower, t) * (1 - f) + sample(upper, t) * f
                let p = SZPoint(scope.x + 1 + x, scope.y + scope.height / 2 - Int((v * amplitude).rounded()))
                if let previous {
                    c.line(from: previous, to: p, color: theme.accentBright)
                }
                previous = p
            }
            c.row(height: 11, gap: 3, align: .center) { row in
                if iconButton(&row, playing ? SZIcons.pause : SZIcons.play, label: playing ? "PAUSE" : "PLAY", on: playing, hint: "RUN THE SCOPE").clicked {
                    playing.toggle()
                }
                label(&row, playing ? "PLAYING" : "PAUSED", color: theme.textDim)
            }
        }

        card(&ctx, "CLIPPING - HITS RESPECT IT") { c in
            c.gap = 4
            let names = ["KICK", "SNARE", "HAT", "CLAP", "TOM", "RIM", "COW", "RIDE", "CRASH", "SHAKE"]
            let cell = 44
            scrollView(&c, axes: .horizontal, content: SZSize(names.count * cell, 13), snap: SZSize(cell, 0), fade: 16, indicators: false, key: "drum-strip", in: c.place(SZSize(0, 13))) { strip, _ in
                for (i, name) in names.enumerated() {
                    let r = SZRect(i * cell, 0, cell - 3, 13)
                    if button(&strip, name, on: drums.contains(i), height: 13, hint: "TOGGLE \(name)", key: .string("drum-\(i)"), in: r).clicked {
                        if drums.contains(i) {
                            drums.remove(i)
                        } else {
                            drums.insert(i)
                        }
                    }
                }
            }
            label(&c, "\(drums.count) OF \(names.count) ON - DRAG SIDEWAYS", color: theme.textDim)
        }

        card(&ctx, "LAYERS - AN OVERLAY ON TOP") { c in
            c.gap = 4
            let items = [SZMenuItem("UNDO", shortcut: "CMD+Z"), SZMenuItem("REDO", shortcut: "CMD+Y"), SZMenuItem("CUT", disabled: true), SZMenuItem("SELECT ALL", shortcut: "CMD+A")]
            c.row(height: 11, gap: 4, align: .center) { row in
                if button(&row, "OPEN THE SHEET", on: sheetOpen, hint: "A MODAL PANEL").clicked {
                    sheetOpen = true
                }
                let anchor = row.place(width: 34, height: 11)
                if button(&row, "MENU", on: menuOpen, hint: "A POPUP MENU", in: anchor).clicked {
                    menuOpen.toggle()
                }
                label(&row, picked.map { "PICKED \($0)" } ?? "NOTHING PICKED", color: theme.textDim)
                let result = menu(&row, isPresented: menuOpen, items: items, anchor: anchor, key: "core-menu")
                if result.dismissed {
                    menuOpen = false
                }
                if let i = result.picked {
                    menuOpen = false
                    post("MENU: \(items[i].label)")
                }
            }
        }

        let presets = ["BLACK GLASS", "AMBER TUBE", "COLD STEEL", "WARM DUST", "NIGHT SHIFT", "LOW SUN", "STATIC"]
        let result = sheet(&ctx, isPresented: sheetOpen, title: "PICK A PRESET", height: 150, key: "preset-sheet") { s in
            s.gap = 2
            for (i, preset) in presets.enumerated() {
                s.row(height: 13, gap: 4, align: .center) { row in
                    let starOn = starred.contains(i)
                    if iconButton(&row, SZIcons.star, label: "STAR \(preset)", on: starOn, size: 13, hint: "FAVORITE", key: .string("star-\(i)")).clicked {
                        if starOn {
                            starred.remove(i)
                        } else {
                            starred.insert(i)
                        }
                    }
                    let rest = SZRect(row.cursor.x + 4, 0, row.bounds.width - row.cursor.x - 4, 13)
                    let it = row.interaction(rest, key: .string("preset-\(i)"))
                    row.accessibility(rest, label: preset, traits: picked == preset ? [.button, .selected] : .button, id: it.id)
                    if it.isActive || row.containsPointer(rest) && row.ui.pointerKind == .mouse {
                        row.fill(rest, color: theme.lineStrong)
                    }
                    row.text(preset, at: SZPoint(rest.x + 4, 3), font: theme.font, color: picked == preset ? theme.accentBright : theme.text)
                    if it.clicked {
                        picked = preset
                        sheetOpen = false
                        post("PICKED \(preset)")
                    }
                }
            }
        }
        if result.dismissed {
            sheetOpen = false
        }
    }
}
