//
//  Gallery+Controls.swift
//  SynthezGallery
//

import Foundation
import SynthezCore
import SynthezWidgets

extension SZGallery {
    func drawControlsLeft(_ ctx: inout SZContext) {
        let theme = ctx.theme
        card(&ctx, "BUTTONS") { c in
            c.gap = 5
            c.row(height: 11, gap: 3, align: .center) { row in
                if button(&row, "SAVE", hint: "WRITE THE PROJECT").clicked {
                    post("SAVED")
                }
                if button(&row, "ARM", on: on, hint: "A LATCHING BUTTON").clicked {
                    on.toggle()
                }
                button(&row, "LOCKED", disabled: true)
                if iconButton(&row, SZIcons.gear, label: "SETTINGS", hint: "AN ICON BUTTON").clicked {
                    post("SETTINGS")
                }
                if iconButton(&row, SZIcons.star, label: "FAVORITE", on: starred.contains(99), hint: "TOGGLE A STAR").clicked {
                    if starred.contains(99) {
                        starred.remove(99)
                    } else {
                        starred.insert(99)
                    }
                }
            }
            c.row(height: 9, gap: 8, align: .center) { row in
                if textButton(&row, "READ THE DOCS", hint: "A TEXT BUTTON").clicked {
                    post("DOCS")
                }
                if textButton(&row, "UNDO", color: theme.text).clicked {
                    post("UNDONE")
                }
            }
        }

        card(&ctx, "CHIPS") { c in
            c.gap = 5
            let names: [SZOption] = ["AMBIENT", "TECHNO", "HOUSE", "ELECTRO", "DRONE", "IDM", "DUB", "GLITCH"]
            if let i = chipGroup(&c, names, selected: genres) {
                if genres.contains(i) {
                    genres.remove(i)
                } else {
                    genres.insert(i)
                }
            }
            let icons = [SZOption("SINE", icon: SZIcons.sine), SZOption("SAW", icon: SZIcons.saw), SZOption("SQUARE", icon: SZIcons.square), SZOption("NOISE", icon: SZIcons.noise)]
            c.row(gap: 6) { row in
                row.column(width: 4 * 20) { chips in
                    if let i = chipGroup(&chips, icons, selected: [waveChip], key: "wave-chips") {
                        waveChip = i
                    }
                }
                label(&row, icons[waveChip].label, color: theme.textDim, in: row.place(width: 40, height: 11))
            }
        }

        card(&ctx, "TOGGLES") { c in
            c.gap = 4
            if checkbox(&c, "MUTE", checked: mute, hint: "SILENCE THE CHANNEL").clicked {
                mute.toggle()
            }
            if checkbox(&c, "SOLO", checked: solo, hint: "ONLY THIS CHANNEL").clicked {
                solo.toggle()
            }
            checkbox(&c, "ALWAYS ON", checked: true, disabled: true)
            if let i = segmented(&c, ["1/4", "1/8", "1/16", "1/32"], selected: division, key: "division") {
                division = i
            }
        }

        card(&ctx, "STEPPERS AND SCRUBBING") { c in
            c.gap = 5
            let colors = ["EMBER", "RUST", "SAND", "BONE", "ASH"]
            let swatches: [SZColor] = [theme.accent, theme.accentDim, theme.textDim, theme.paper, theme.lineStrong]
            c.row(height: 13, gap: 6, align: .center) { row in
                let step = stepper(&row, colors[colorIndex], swatch: swatches[colorIndex], width: 80, previousDisabled: colorIndex == 0, nextDisabled: colorIndex == colors.count - 1, hint: "PICK A COLOR")
                colorIndex = min(max(colorIndex + step, 0), colors.count - 1)
                let octaveStep = stepper(&row, "OCT \(octave)", width: 64, previousDisabled: octave == 0, nextDisabled: octave == 8, hint: "OCTAVE", key: "octave")
                octave = min(max(octave + octaveStep, 0), 8)
            }
            c.row(height: 11, gap: 5, align: .center) { row in
                label(&row, "BPM", color: theme.textDim)
                if let v = scrubValue(&row, value: bpm, in: 40 ... 240, look: .underline, label: "BPM", hint: "DRAG SIDEWAYS") {
                    bpm = v
                }
                label(&row, "SWING", color: theme.textDim)
                if let v = scrubValue(&row, value: swing, in: 0 ... 1, step: 0.01, look: .outline, dragPixels: 2, width: 36, label: "SWING", hint: "DRAG SIDEWAYS", key: "swing") {
                    swing = v
                }
            }
        }
    }

    func drawControlsRight(_ ctx: inout SZContext) {
        let theme = ctx.theme
        card(&ctx, "MENUS") { c in
            c.gap = 5
            let types = [SZMenuItem("LOWPASS"), SZMenuItem("HIGHPASS"), SZMenuItem("BANDPASS"), SZMenuItem("NOTCH"), SZMenuItem("COMB", disabled: true)]
            c.row(height: 13, gap: 6, align: .center) { row in
                label(&row, "FILTER", color: theme.textDim)
                if let i = dropdown(&row, types, selected: filterType, width: 80, hint: "FILTER TYPE") {
                    filterType = i
                    post("FILTER: \(types[i].label)")
                }
            }
        }

        card(&ctx, "KNOBS") { c in
            c.row(gap: 6) { row in
                let titles = ["CUTOFF", "RES", "DRIVE", "PAN", "STEP"]
                for i in knobs.indices {
                    let bipolar = i == 3
                    let text: String? = switch i {
                    case 3: knobs[i] == 0.5 ? "C" : (knobs[i] < 0.5 ? "L" : "R") + String(Int((abs(knobs[i] - 0.5) * 200).rounded()))
                    case 4: String(Int((knobs[i] * 7).rounded()) + 1)
                    default: nil
                    }
                    if let v = knob(&row, titles[i], value: knobs[i], bipolar: bipolar, steps: i == 4 ? 8 : nil, reset: bipolar ? 0.5 : 0.5, text: text, hint: "DRAG UP OR DOWN; DOUBLE-TAP RESETS", key: .string("knob-\(i)")) {
                        knobs[i] = v
                    }
                }
            }
        }

        card(&ctx, "SLIDERS") { c in
            c.gap = 5
            c.row(height: 9, gap: 6, align: .center) { row in
                label(&row, "CUTOFF", color: theme.textDim, in: row.place(width: 38, height: 9))
                if let v = slider(&row, value: cutoff, reset: 0.35, length: row.bounds.width - row.cursor.x - 30, label: "CUTOFF", hint: "DOUBLE-TAP RESETS") {
                    cutoff = v
                }
                label(&row, String(Int(cutoff * 100)), color: theme.text)
            }
            c.row(height: 9, gap: 6, align: .center) { row in
                label(&row, "BAL", color: theme.textDim, in: row.place(width: 38, height: 9))
                if let v = slider(&row, value: balance, range: -1 ... 1, bipolar: true, reset: 0, length: row.bounds.width - row.cursor.x - 30, label: "BALANCE") {
                    balance = v
                }
                label(&row, String(Int(balance * 100)), color: theme.text)
            }
            c.row(height: 56, gap: 8) { row in
                let bands = ["LOW", "MID", "HI", "AIR"]
                for i in eq.indices {
                    row.column(width: 18, gap: 2, align: .center) { band in
                        if let v = slider(&band, value: eq[i], step: 1.0 / 24, axis: .vertical, bipolar: false, reset: 0.5, length: 44, label: bands[i], key: .string("eq-\(i)")) {
                            eq[i] = v
                        }
                        label(&band, bands[i], color: theme.textDim)
                    }
                }
            }
        }

        card(&ctx, "PADS") { c in
            let columns = max((c.bounds.width + 3) / 31, 1)
            let cell = SZSize(28, 11)
            var y = 0
            for row in 0 ..< (gridCount + columns - 1) / columns {
                for column in 0 ..< columns {
                    let index = row * columns + column
                    guard index < gridCount else { break }
                    let r = SZRect(column * (cell.width + 3), y, cell.width, cell.height)
                    if button(&c, String(index), on: pad == index, height: cell.height, key: .int(1000 + index), in: r).clicked {
                        pad = index
                    }
                }
                y += cell.height + 3
            }
            c.place(SZSize(0, max(y - 3, 0)))
        }
    }

    func drawTextLeft(_ ctx: inout SZContext) {
        let theme = ctx.theme
        card(&ctx, "TITLE - DOUBLE SIZE") { c in
            let result = textField(&c, value: title, placeholder: "NAME THE SONG", maxLength: 24, scale: 2, label: "TITLE", hint: "TAP TO EDIT", key: "title")
            if result.committed {
                title = result.text
                log.append("TITLE: \(result.text)")
                post("TITLE SAVED")
            }
        }

        card(&ctx, "FIELDS") { c in
            c.gap = 5
            c.row(height: 13, gap: 6, align: .center) { row in
                label(&row, "NAME", color: theme.textDim, in: row.place(width: 30, height: 13))
                let result = textField(&row, value: name, placeholder: "16 CHARS MAX", maxLength: 16, width: row.bounds.width - row.cursor.x - 6, label: "NAME", key: "name")
                if result.committed {
                    name = result.text
                    log.append("NAME: \(result.text.isEmpty ? "-" : result.text)")
                }
            }
            c.row(height: 13, gap: 6, align: .center) { row in
                label(&row, "BPM", color: theme.textDim, in: row.place(width: 30, height: 13))
                let result = textField(&row, value: digits, placeholder: "DIGITS", maxLength: 3, allowed: { $0.isNumber }, numeric: true, width: 40, label: "DIGITS", hint: "NUMBERS ONLY", key: "digits")
                if result.committed {
                    digits = result.text
                    log.append("BPM: \(result.text)")
                }
                label(&row, "NUMBERS ONLY", color: theme.textDim)
            }
            c.row(height: 13, gap: 6, align: .center) { row in
                label(&row, "NOTE", color: theme.textDim, in: row.place(width: 30, height: 13))
                let result = textField(&row, value: note, width: row.bounds.width - row.cursor.x - 6, label: "NOTE", hint: "LONG TEXT SCROLLS", key: "note")
                if result.committed {
                    note = result.text
                    log.append("NOTE SAVED")
                }
            }
        }
    }

    func drawTextRight(_ ctx: inout SZContext) {
        let theme = ctx.theme
        card(&ctx, "LOG - LAST SUBMISSIONS") { c in
            c.gap = 2
            if log.isEmpty {
                label(&c, "NOTHING YET - EDIT A FIELD", color: theme.textDim)
            }
            for (i, entry) in log.suffix(5).enumerated() {
                label(&c, "\(log.count - min(log.count, 5) + i + 1). \(entry)", color: i == min(log.count, 5) - 1 ? theme.paper : theme.text)
            }
            if !log.isEmpty, textButton(&c, "CLEAR").clicked {
                log.removeAll()
            }
        }

        card(&ctx, "PARAGRAPH - WRAPS TO FIT") { c in
            c.gap = 5
            if let i = segmented(&c, ["LEFT", "CENTER", "RIGHT"], selected: alignment, key: "align") {
                alignment = i
            }
            let align: SZAlignment = [.start, .center, .end][alignment]
            paragraph(&c, "PIXEL TEXT BREAKS AT SPACES. A LAYOUT IS KEPT WHILE ITS TEXT AND WIDTH STAY THE SAME, SO WRAPPING COSTS NOTHING ON IDLE FRAMES.", color: theme.text, align: align)
        }
    }
}
