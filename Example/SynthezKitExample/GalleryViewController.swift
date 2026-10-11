//
//  GalleryViewController.swift
//  SynthezKitExample
//

import SynthezGallery
import SynthezKit
import SynthezWidgets
import UIKit

final class GalleryViewController: UIViewController {
    private let gallery = SZGallery(gridCount: 24)
    private let canvas = SZCanvasView(palette: SZTheme.synthPalette(), background: 1, resolution: .pixelScale(3))

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0x14 / 255, green: 0x11 / 255, blue: 0x0F / 255, alpha: 1)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        let gallery = gallery
        canvas.body = { [weak canvas] ctx in
            gallery.draw(&ctx)
            canvas?.crt = gallery.crt
        }
    }

    override var prefersStatusBarHidden: Bool {
        false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }
}
