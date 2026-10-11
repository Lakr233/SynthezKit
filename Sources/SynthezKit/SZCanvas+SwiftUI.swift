//
//  SZCanvas+SwiftUI.swift
//  SynthezKit
//

import SwiftUI

/// A SwiftUI view that hosts an ``SZCanvasView``.
///
/// ```swift
/// struct ContentView: View {
///     let model = Model()   // a class: the body reads and writes it every frame
///
///     var body: some View {
///         SZCanvas(palette: SZTheme.synthPalette(), background: 1) { ctx in
///             if button(&ctx, "+").clicked { model.count += 1 }
///             label(&ctx, String(model.count))
///         }
///     }
/// }
/// ```
///
/// The body runs once per frame, not when SwiftUI re-renders, so keep the
/// state it reads in a reference type. Changes to the arguments, such as a
/// new `crt`, apply on the next SwiftUI update; call ``SZCanvasView/invalidate()``
/// from `configure` to redraw after outside state changes.
public struct SZCanvas: View {
    let palette: SZPalette
    let background: SZColor
    let resolution: SZResolution
    let crt: SZCRTSettings?
    let configure: (@MainActor (SZCanvasView) -> Void)?
    let content: (inout SZContext) -> Void

    /// - Parameters:
    ///   - crt: The CRT settings, or nil to leave them to the view (for
    ///     example, set from the body through `configure`'s view).
    ///   - configure: Called once with the view after it is created, for
    ///     anything the wrapper does not expose.
    ///   - content: The immediate-mode body, run every frame.
    public init(
        palette: SZPalette,
        background: SZColor = 0,
        resolution: SZResolution = .pixelScale(3),
        crt: SZCRTSettings? = nil,
        configure: (@MainActor (SZCanvasView) -> Void)? = nil,
        content: @escaping (inout SZContext) -> Void,
    ) {
        self.palette = palette
        self.background = background
        self.resolution = resolution
        self.crt = crt
        self.configure = configure
        self.content = content
    }

    public var body: some View {
        SZCanvasRepresentable(canvas: self)
    }
}

struct SZCanvasRepresentable {
    let canvas: SZCanvas

    @MainActor func makeView() -> SZCanvasView {
        let view = SZCanvasView(palette: canvas.palette, background: canvas.background, resolution: canvas.resolution)
        update(view)
        canvas.configure?(view)
        return view
    }

    @MainActor func update(_ view: SZCanvasView) {
        if view.ui.palette !== canvas.palette {
            view.ui.palette = canvas.palette
        }
        if view.ui.background != canvas.background {
            view.ui.background = canvas.background
        }
        view.resolution = canvas.resolution
        if let crt = canvas.crt {
            view.crt = crt
        }
        view.body = canvas.content
    }
}

#if canImport(UIKit)
    import UIKit

    extension SZCanvasRepresentable: UIViewRepresentable {
        func makeUIView(context _: Context) -> SZCanvasView {
            makeView()
        }

        func updateUIView(_ view: SZCanvasView, context _: Context) {
            update(view)
        }
    }
#else
    #if canImport(AppKit)
        import AppKit

        extension SZCanvasRepresentable: NSViewRepresentable {
            func makeNSView(context _: Context) -> SZCanvasView {
                makeView()
            }

            func updateNSView(_ view: SZCanvasView, context _: Context) {
                update(view)
            }
        }
    #endif
#endif
