//
//  Gallery+Scroll.swift
//  SynthezGallery
//

import Foundation
import SynthezCore
import SynthezWidgets

extension SZGallery {
    func drawScrollPage(_ ctx: inout SZContext, isWide: Bool) {
        let theme = ctx.theme
        let total = ctx.bounds.height
        let listHeight = isWide ? total : total * 45 / 100

        let listArea = isWide ? ctx.cutLeft((ctx.bounds.width - 8) / 2, gap: 8) : ctx.cutTop(listHeight, gap: 6)
        ctx.region(listArea) { area in
            let head = area.cutTop(9, gap: 3)
            area.text("LIST - 10,000 ROWS, ONLY VISIBLE ONES BUILT", at: head.origin, font: theme.font, color: theme.textDim)
            let tapped = list(&area, count: 10000, rowHeight: 13, selected: selectedRow, key: "big-list", in: area.bounds) { row, info in
                let level = 0.5 + 0.5 * sin(Double(info.index) * 0.37) * cos(Double(info.index) * 0.11)
                let ink = info.selected ? theme.paper : theme.text
                row.text(String(format: "TRACK %05d", info.index + 1), at: SZPoint(6, 3), font: theme.font, color: ink)
                let meter = SZRect(row.bounds.width - 70, 4, 60, 5)
                row.fill(meter, color: theme.background)
                row.fill(SZRect(meter.x, meter.y, Int(Double(meter.width) * level), meter.height), color: info.selected ? theme.accentBright : theme.accentDim)
            }
            if let tapped {
                selectedRow = tapped
                post(String(format: "TRACK %05d", tapped + 1))
            }
        }

        let channelHeight = 78
        let channelArea = ctx.cutTop(channelHeight + 12, gap: 6)
        ctx.region(channelArea) { area in
            let head = area.cutTop(9, gap: 3)
            area.text("CHANNELS - SNAPS TO A STRIP", at: head.origin, font: theme.font, color: theme.textDim)
            let frame = area.bounds
            area.fill(frame, color: theme.panel)
            area.stroke(frame, color: theme.line)
            let strip = 44
            scrollView(&area, axes: .horizontal, content: SZSize(channels.count * strip + 4, frame.height - 2), snap: SZSize(strip, 0), fade: 20, key: "channels", in: frame.inset(by: 1)) { c, _ in
                for i in channels.indices {
                    let x = 4 + i * strip
                    c.region(SZRect(x, 4, strip - 6, frame.height - 10), key: .string("channel-\(i)")) { ch in
                        ch.fill(ch.bounds, color: theme.background)
                        ch.stroke(ch.bounds, color: theme.lineStrong)
                        ch.text(String(format: "CH%02d", i + 1), at: SZPoint(4, 3), font: theme.font, color: theme.textDim)
                        if let v = slider(&ch, value: channels[i], axis: .vertical, reset: 0.5, label: String(format: "CHANNEL %d", i + 1), key: .string("fader-\(i)"), in: SZRect((ch.bounds.width - 9) / 2, 13, 9, ch.bounds.height - 26)) {
                            channels[i] = v
                        }
                        let db = Int((channels[i] * 60 - 48).rounded())
                        let text = "\(db)"
                        ch.text(text, at: SZPoint((ch.bounds.width - theme.font.measure(text)) / 2, ch.bounds.height - 10), font: theme.font, color: theme.text)
                    }
                }
            }
        }

        ctx.region(ctx.bounds) { area in
            let head = area.cutTop(9, gap: 3)
            area.text("SELF-MEASURED - CONTENT SIZES ITSELF", at: head.origin, font: theme.font, color: theme.textDim)
            let frame = area.bounds
            area.fill(frame, color: theme.panel)
            area.stroke(frame, color: theme.line)
            scrollView(&area, fade: 12, key: "notes", in: frame.inset(by: 1)) { c, _ in
                c.inset(top: 4, right: 8, bottom: 4, left: 6)
                c.gap = 6
                let notes = [
                    "IMMEDIATE MODE: THE WHOLE SCREEN IS DESCRIBED AGAIN EVERY FRAME, AND ONLY WHAT CHANGED IS DRAWN.",
                    "THE SCROLL VIEW MEASURES THIS TEXT AS IT IS LAID OUT AND USES THE SIZE NEXT FRAME.",
                    "FLING IT: VELOCITY DECAYS LIKE UIKIT, AND THE EDGES STRETCH AND SPRING BACK.",
                    "THE FADE AT EACH EDGE GROWS WITH HOW MUCH CONTENT HIDES BEYOND IT.",
                    "WHEN NOTHING MOVES, THE DISPLAY LINK PAUSES AND THE CANVAS COSTS NOTHING.",
                ]
                for (i, note) in notes.enumerated() {
                    c.row(gap: 4) { row in
                        label(&row, String(format: "%02d", i + 1), color: theme.accent, in: row.place(width: 12, height: 7))
                        row.column(width: row.bounds.width - 16) { col in
                            paragraph(&col, note, color: theme.text)
                        }
                    }
                }
            }
        }
    }
}
