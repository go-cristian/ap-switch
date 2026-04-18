import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let panel: NSPanel
    private let model: SwitcherOverlayModel

    init(model: SwitcherOverlayModel) {
        self.model = model

        let initialSize = CGSize(width: 1680, height: 304)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: SwitcherOverlayView(model: model, overlaySize: initialSize))
    }

    func show() {
        guard let screen = targetScreen() else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let size = panelSize(for: visibleFrame)
        let origin = NSPoint(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.midY - (size.height / 2)
        )

        panel.contentView = NSHostingView(rootView: SwitcherOverlayView(model: model, overlaySize: size))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func panelSize(for visibleFrame: NSRect) -> CGSize {
        let width = min(max(visibleFrame.width - 72, 1480), 1800)
        let height = min(max(visibleFrame.height * 0.30, 292), 320)
        return CGSize(width: width, height: height)
    }
}
