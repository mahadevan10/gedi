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

/// Transparent, always-on-top strip along the bottom of the screen. Click-through except
/// over Gedi himself (the controller toggles `ignoresMouseEvents`); his mouse events go to `onMouse`.
final class OverlayPanel: NSPanel {
    var onMouse: ((NSEvent) -> Void)?

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

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown: onMouse?(event)
        default: super.sendEvent(event)
        }
    }
}

@MainActor
final class OverlayController: NSObject {
    static let height: CGFloat = 240
    private let panel: OverlayPanel
    private let stage: StageModel
    private let onPinned: () -> Void
    private var timer: Timer?
    private var lastStep = Date()
    private var rng = SystemRandomNumberGenerator()
    /// Last mouse position while dragging Gedi; nil when not dragging.
    private var dragFrom: NSPoint?
    private var dragged = false

    init(stage: StageModel, onPinned: @escaping () -> Void) {
        self.stage = stage
        self.onPinned = onPinned
        panel = OverlayPanel(frame: Self.frameForMainScreen())
        super.init()
        panel.contentView = NSHostingView(rootView: StageView(stage: stage))
        panel.onMouse = { [weak self] in self?.mouse($0) }
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
        // Catch clicks only over Gedi; everywhere else the strip stays click-through.
        if dragFrom == nil {
            let sprite = NSRect(x: panel.frame.minX + stage.walker.x, y: panel.frame.minY,
                                width: StageView.spriteWidth, height: StageView.spriteHeight)
            panel.ignoresMouseEvents = !sprite.contains(NSEvent.mouseLocation)
        }
    }

    // MARK: mouse: drag to move and pin, click for the menu

    private func mouse(_ event: NSEvent) {
        let at = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            dragFrom = at
            dragged = false
        case .leftMouseDragged:
            guard let from = dragFrom else { return }
            dragged = true
            stage.walker.pinned = true
            dragFrom = at
            let maxX = Double(panel.frame.width) - StageView.spriteWidth
            stage.walker.x = min(max(stage.walker.x + at.x - from.x, 0), maxX)
            let screen = (panel.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            let y = min(max(panel.frame.minY + at.y - from.y, screen.minY), screen.maxY - panel.frame.height)
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: y))
        case .leftMouseUp:
            dragFrom = nil
            if dragged { onPinned() } else { showMenu(event) }
        default:
            showMenu(event)
        }
    }

    private func showMenu(_ event: NSEvent) {
        let menu = NSMenu()
        let pinned = stage.walker.pinned
        let item = NSMenuItem(title: pinned ? "Unpin (let him walk)" : "Pin here",
                              action: #selector(togglePin), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        let hint = NSMenuItem(title: "Drag him to pin him anywhere", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        if let view = panel.contentView { NSMenu.popUpContextMenu(menu, with: event, for: view) }
    }

    @objc private func togglePin() {
        stage.walker.pinned.toggle()
        if stage.walker.pinned {
            onPinned()
        } else {
            panel.setFrame(Self.frameForMainScreen(), display: true)  // back down to the Dock
        }
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
