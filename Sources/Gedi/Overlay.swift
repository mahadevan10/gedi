import AppKit
import GediCore
import SwiftUI

/// What the overlay draws. The controller changes it; SwiftUI redraws.
@Observable
@MainActor
final class StageModel {
    var walker = Walker(x: 200)
    var bubble: String?

    func setTalking(_ talking: Bool) {
        walker.setTalking(talking)
    }
}

/// Transparent, click-through, always-on-top strip along the bottom of the screen.
final class OverlayPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    static let height: CGFloat = 240
    private let panel: OverlayPanel
    private let stage: StageModel
    private var timer: Timer?
    private var lastStep = Date()
    private var rng = SystemRandomNumberGenerator()

    init(stage: StageModel) {
        self.stage = stage
        panel = OverlayPanel(frame: Self.frameForMainScreen())
        panel.contentView = NSHostingView(rootView: StageView(stage: stage))
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.setFrame(Self.frameForMainScreen(), display: true) }
        }
    }

    /// Bottom strip of the main screen's visible area, i.e. just above the Dock.
    static func frameForMainScreen() -> NSRect {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: height)
    }

    func show() {
        panel.orderFrontRegardless()
        lastStep = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    private func step() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastStep), 0.1)
        lastStep = now
        let maxX = Double(panel.frame.width) - StageView.spriteWidth
        stage.walker.step(dt: dt, minX: 0, maxX: maxX, random: &rng)
    }
}

struct StageView: View {
    static let pixel: CGFloat = 4
    static let spriteWidth = Double(SpriteArt.width) * Double(pixel)
    static let spriteHeight = Double(SpriteArt.height) * Double(pixel)
    static let bubbleWidth: Double = 320

    let stage: StageModel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Color.clear
                SpriteView(frame: stage.walker.frame, facingRight: stage.walker.facingRight)
                    .offset(x: stage.walker.x)
                if let text = stage.bubble {
                    BubbleView(text: text)
                        .frame(maxWidth: Self.bubbleWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(x: bubbleX(width: geo.size.width), y: -(Self.spriteHeight + 8))
                }
            }
        }
    }

    /// Keep the bubble over Gedi but fully on screen.
    private func bubbleX(width: Double) -> Double {
        min(max(stage.walker.x - 40, 0), max(width - Self.bubbleWidth, 0))
    }
}

struct SpriteView: View {
    let frame: SpriteFrame
    let facingRight: Bool

    var body: some View {
        Canvas { ctx, _ in
            let p = StageView.pixel
            for (y, row) in SpriteArt.rows(frame).enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let rgb = SpriteArt.palette[ch] else { continue }
                    let rect = CGRect(x: CGFloat(x) * p, y: CGFloat(y) * p, width: p, height: p)
                    ctx.fill(Path(rect), with: .color(Color(rgb: rgb)))
                }
            }
        }
        .frame(width: StageView.spriteWidth, height: StageView.spriteHeight)
        .scaleEffect(x: facingRight ? 1 : -1, y: 1)
    }
}

struct BubbleView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.25)))
            .shadow(radius: 3)
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}
