import AppKit
import ApplicationServices
import Combine

@MainActor
final class AccessibilityPermissionController: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    func refreshStatus() {
        isTrusted = AXIsProcessTrusted()
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
