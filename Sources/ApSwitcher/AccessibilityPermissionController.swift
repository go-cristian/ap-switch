import AppKit
@preconcurrency import ApplicationServices
import Combine

@MainActor
final class AccessibilityPermissionController: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    func refreshStatus() {
        isTrusted = AXIsProcessTrusted()
    }

    @discardableResult
    func requestIfNeeded() -> Bool {
        refreshStatus()
        guard !isTrusted else {
            return true
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        return isTrusted
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
