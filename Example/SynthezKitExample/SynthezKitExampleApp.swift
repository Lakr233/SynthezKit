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
        .defaultSize(width: 1280, height: 800)
        #endif
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

    // One virtual pixel per point on phones; bigger pixels on the Mac,
    // where windows are wide and seen from further away.
    #if canImport(UIKit)
        static let resolution = SZResolution.pointScale(1)
    #else
        static let resolution = SZResolution.pointScale(1.5)
    #endif
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
