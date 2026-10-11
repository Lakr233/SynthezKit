# Benchmarks

`swift run -c release SynthezBench 2000` runs every gallery page headlessly at a virtual 640×400: 60 warm-up frames, then 2,000 measured frames, once idle and once with a pointer sweeping across the page. Each frame is timed in two parts:

- **build**: `SZUI.frame`, which routes input, runs the body, builds the draw list and compares it with the previous one;
- **raster**: `SZSurface.render`, timed only for frames whose draw list changed.

The figures below come from an Apple M4 virtual machine with 10 cores. An iPhone's single-core speed is in the same range; budget twice the figures for older devices. At 120 Hz a frame has 8.3 ms.

## Frame cost per page (µs, p50 / p95 of build plus raster)

| Page | Commands | Idle | Interactive |
| --- | --- | --- | --- |
| Core (with dither, steps and radial filters) | 479 | 35 / 40 | 36 / 144 |
| Controls | 449 | 39 / 40 | 40 / 89 |
| Text | 66 | 13 / 14 | 13 / 17 |
| Scroll (10,000-row virtual list) | 201 | 77 / 91 | 78 / 163 |
| CRT (bar sweeping every frame) | 135 | 48 / 53 | 48 / 59 |
| Controls with 640 pads | 594 | — | 132 / 206 |

## Notes

- Idle frames cost only the body: the draw list matches the previous one, so nothing is rasterized or uploaded. In the app, the display link pauses, and the process uses no CPU on a still page.
- Rasterizing a full 640×400 frame takes about 30–45 µs. Per-pixel filters dominate the Core page's raster time (about 100 µs); a constant-strength filter collapses into a single color-map pass.
- The heaviest scenario, 640 buttons, spends about 0.15 µs per button building the frame, mostly formatting labels and looking up the theme.
- On the iOS simulator in a debug build, the example app uses 0% CPU on a still page and about 26–30% while the scope or CRT sweep animates, including simulator overhead.

Compare against these tables after any change that touches the frame path.
