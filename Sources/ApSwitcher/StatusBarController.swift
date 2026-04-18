import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    override init() {
        super.init()
        configureStatusItem()
        refreshMenu()
    }

    func refreshMenu() {
        let menu = NSMenu()
        let closeItem = NSMenuItem(title: "Cerrar", action: #selector(quit), keyEquivalent: "q")
        closeItem.target = self
        menu.addItem(closeItem)
        statusItem.menu = menu
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "ApSwitcher")
            button.imagePosition = .imageOnly
            button.toolTip = "ApSwitcher"
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
