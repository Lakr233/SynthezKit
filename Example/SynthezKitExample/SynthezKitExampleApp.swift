//
//  SynthezKitExampleApp.swift
//  SynthezKitExample
//

import SwiftUI
import SynthezGallery
import SynthezKit
import SynthezWidgets

@main
struct SynthezKitExampleApp: App {
    var body: some Scene {
        WindowGroup {
            GalleryView()
                .ignoresSafeArea(.keyboard)
        }
        #if !canImport(UIKit) && canImport(AppKit)
        .defaultSize(Self.windowSize)
        #endif
    }

    /// `-SZWindowSize 1280x960` sizes the Mac window, for screenshots.
    static var windowSize: CGSize {
        let parts = (UserDefaults.standard.string(forKey: "SZWindowSize") ?? "").split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : CGSize(width: 1280, height: 800)
    }
}

/// The gallery in a SwiftUI canvas. The canvas body reads and writes the
/// gallery, a class, every frame, and hands its CRT settings to the view.
@MainActor
final class GalleryModel {
    let gallery = SZGallery(gridCount: 24)
    let palette = SZTheme.synthPalette()
    weak var canvas: SZCanvasView?
    var tour: DemoTour?

    /// One virtual pixel per point on phones; bigger pixels on the Mac,
    /// where windows are wide and seen from further away.
    /// `-SZPointScale 2` overrides it, for screenshots.
    static var resolution: SZResolution {
        let override = UserDefaults.standard.double(forKey: "SZPointScale")
        if override > 0 {
            return .pointScale(override)
        }
        #if canImport(UIKit)
            return .pointScale(1)
        #else
            return .pointScale(1.5)
        #endif
    }
}

struct GalleryView: View {
    @State private var model = GalleryModel()

    var body: some View {
        let model = model
        SZCanvas(palette: model.palette, background: 1, resolution: GalleryModel.resolution) { view in
            model.canvas = view
            // `-SZDemoTour YES` walks through every page, for recordings.
            if UserDefaults.standard.bool(forKey: "SZDemoTour") {
                let tour = DemoTour(canvas: view)
                model.tour = tour
                tour.run()
            }
        } content: { ctx in
            model.gallery.draw(&ctx)
            model.canvas?.crt = model.gallery.crt
        }
        .background(Color(red: 0x14 / 255, green: 0x11 / 255, blue: 0x0F / 255))
    }
}
