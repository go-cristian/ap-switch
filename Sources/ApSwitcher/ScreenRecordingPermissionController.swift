import AppKit
import CoreGraphics

@MainActor
final class ScreenRecordingPermissionController: ObservableObject {
    @Published private(set) var isGranted = CGPreflightScreenCaptureAccess()

    func refreshStatus() {
        isGranted = CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    func requestIfNeeded() -> Bool {
        refreshStatus()
        guard !isGranted else {
            return true
        }

        isGranted = CGRequestScreenCaptureAccess()
        return isGranted
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
