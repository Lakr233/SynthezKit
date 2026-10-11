# Design

SynthezKit brings the model of [synth-ui](https://github.com/unixzii/synth-ui) (TypeScript components on a Rust and wgpu backend) to Swift and UIKit, driven by [DisplayLink](https://github.com/Lakr233/DisplayLink) and built with the conventions of [Litext](https://github.com/Lakr233/Litext).

## What synth-ui does, and what carries over

- **The GPU does not draw the UI.** synth-ui rasterizes every frame on the CPU into an 8-bit palette-indexed framebuffer (one byte per pixel; 256 KB at 640×400). The GPU uploads it, resolves palette colors, scales it, and runs the CRT post-process. SynthezKit keeps this split: index-reading operations such as `remap`, `mosaic` and `filter` are trivial on a CPU framebuffer and awkward on a GPU.
- **Draw lists bucketed by layer.** Overlays are drawn in the middle of their parents but must land on top, so commands collect per layer and replay layer by layer. Every command carries a clip index, so replay needs no clip stack.
- **Identity from position.** A region's children derive their keys from the region's key plus a running counter; an explicit key replaces the path where order can change. Widgets take one key and name their parts. State not touched in a frame is released.
- **Input routed against the previous frame.** Each interaction registers its clipped rectangle; the next frame hit-tests those rectangles, so a widget learns about its input in the same call that draws it. The highest layer under the pointer wins, and within a layer, the last rectangle registered. Senses (`click`, `wheel`, `focus`, `hover`, `drag`) are routed separately, so wheel and drag gestures pass through buttons to the scroll view beneath.
- **Cursor-and-cut layout.** `place`, `row`, `column` and RectCut-style `cutTop/Bottom/Left/Right` on whole virtual pixels. Natural sizes come from what children reached; scroll views and cards use the size measured on the previous frame, which avoids a second layout pass.
- **No alpha.** Transparency effects come from 4×4 Bayer patterns, palette color maps (nearest neighbor in OKLab, quantized to 1/32), dither or step filters over strength fields, and mosaic.
- **Frame-rate-independent easing** and a scheduler that draws only when something is dirty, moving, receiving input, or still glowing.

## What changed for Swift and UIKit

| Concern | synth-ui | SynthezKit |
| --- | --- | --- |
| Language boundary | One FFI call per primitive | None; widgets append to the draw list directly |
| Keys | Concatenated strings | `SZID`, a 64-bit SplitMix hash chain; no allocation |
| Regions | A new `Context` object per region | `SZContext` is a struct passed `inout` to non-escaping closures |
| State | `Map<string, any>` | Typed boxes created once; animations stored as plain `Double`s |
| Commands | Strings and bitmaps cloned per command | Glyph indices in a shared per-frame arena; storage reused between frames |
| Idle frames | Not drawn | Not drawn, identical draw lists skip rasterizing and uploading, and the display link pauses |
| Upload | One texture per frame | Three rotating `r8Uint` textures; a frame is dropped rather than blocking the main thread |
| Input | Mouse | Touch: held implies hover, drags capture, flings decelerate like `UIScrollView`, edges rubber-band, input trickles |
| Accessibility | ARIA labels | Every interactive widget is a `UIAccessibilityElement` that activates and adjusts |

## Modules

```
SynthezCore     Foundation only; runs under `swift test` on macOS
  Geometry      SZPoint, SZSize, SZRect in whole virtual pixels
  Color         SZPalette (OKLab), SZColorMap, strength fields and filter maps
  Bitmap        SZBitmap (1 bit, one UInt64 per row), Bayer patterns
  Font          SZBitmapFont (glyphs as strings; ASCII table plus dictionary), text layout and its cache
  Draw          SZDrawList: layered commands with inline payloads, comparable frame to frame
  Raster        SZSurface: the indexed framebuffer and every primitive
  UI            SZUI (cross-frame state), SZContext (a region), SZID
  Input         Events, senses, interactions, accessibility items
  Animation     Exponential easing independent of frame rate
  Schedule      SZFrameScheduler, SZScreen (fixed resolution or pixel scale), SZCRTSettings
SynthezWidgets  Theme, font, icons, widgets
SynthezKit      SZCanvasView, SZMetalPresenter, keyboard proxy, accessibility elements
SynthezGallery  The five demo pages
SynthezBench    Headless timings and PNG snapshots
```

## Frame lifecycle

1. Touches, keys and wheel events queue on the canvas and wake its `DisplayLink`.
2. On the next refresh, the scheduler decides whether a frame is due: something invalidated, input arrived, an animation asked for another frame, a timed wake (such as a caret blink) is reached, or CRT afterglow is still fading.
3. `SZUI.frame` applies the events, trickled so that a press and its release never take effect in the same frame, then runs the body.
4. The finished draw list is compared with the previous one. Only a changed list is rasterized and uploaded; with CRT on, frames are still presented while the afterglow fades.
5. A frame that applied input always asks for one more, because widgets draw before they react to their own clicks.
6. With nothing pending, the display link pauses.

Animation time comes from the display link's `targetTimestamp`. After an idle stretch the first frame advances by one nominal frame rather than by the time spent idle, so animations start from their first step.

## CRT pipeline

All in linear light, per frame:

1. **Phosphor.** Each channel shows the new frame or its previous light times `exp(-dt / τ)`, whichever is brighter. Red decays slowest.
2. **Halation.** A chain of half-size levels blurred down with a 5-tap kernel and added back up with an 8-tap tent.
3. **Present.** Five neighboring rows contribute Gaussian beams whose width grows with brightness, so dark lines show gaps and bright lines swell; a compensated aperture, slot or shadow mask; the glow without lines or mask; vignette; glass reflection; sRGB encoding.

When CRT is off, a single pass resolves palette colors with sharp-bilinear scaling, which blends only within the device pixel that straddles a virtual pixel edge, so fractional scales stay crisp.

## Status

| Area | State |
| --- | --- |
| Core layout, identity, routing, raster, filters | Done |
| Widgets listed in the README | Done |
| Metal presentation, CRT, keyboard, accessibility | Done |
| Example app | Done |
| IME marked text and text selection (needs full `UITextInput`) | Planned |
| CJK text (CoreText rasterized to 1 bit, with a glyph cache) | Planned |
| Hardware keyboard shortcut table | Planned |
| CRT burn-in | Planned |
| Dirty-rectangle or tiled rasterization | Planned, not needed at current timings |

## Bugs found by driving the example app

The example app was exercised on the iOS simulator with scripted touches located through accessibility, recorded, and checked frame by frame. That surfaced three framework bugs, each now covered by a test:

1. **Animations jumped after idle.** The first frame after the display link resumed used the whole idle time as its step, so eased values covered most of their distance in one frame.
2. **State changed by input was not drawn.** A widget draws before it reports its click; when the click changed state and the draw list happened to match the previous frame, no further frame was scheduled. A frame that applies input, including deferred input, now always requests one more.
3. **Gestures inside one frame lost their drag.** During a hitch, a press, its moves and its release could all be applied before any widget ran, so scroll views never saw the pointer down. Input now trickles like Dear ImGui's.
