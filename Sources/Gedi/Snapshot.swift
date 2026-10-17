import AppKit
import GediCore
import SwiftUI

/// `Gedi --snapshot out.png` renders the stage with a sample bubble to a PNG and exits.
/// Lets you check the art and bubble layout without screen-recording permission.
@MainActor
enum Snapshot {
    static func write(to url: URL) throws {
        let stage = StageModel()
        stage.walker = Walker(x: 120)
        stage.bubble = "എന്തൂട്ടാ ഗഡീ ഇത്? പിന്നേം ഷോർട്സ്? ആ ടാബ് ഒന്ന് അടച്ചിട്ട് പണി തീർക്ക് ഇഷ്ടാ."
        let view = StageView(stage: stage)
            .frame(width: 600, height: OverlayController.height)
            .background(Color(white: 0.85))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
        print("wrote \(url.path)")
    }
}
