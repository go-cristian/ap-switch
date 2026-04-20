import Foundation

@MainActor
final class WindowUsageTracker {
    private let focusedWindowProvider: () -> WindowIdentity?
    private var pollTimer: Timer?
    private(set) var recentWindows: [WindowIdentity] = []

    init(focusedWindowProvider: @escaping () -> WindowIdentity?) {
        self.focusedWindowProvider = focusedWindowProvider
    }

    func start() {
        guard pollTimer == nil else {
            return
        }

        noteCurrentWindow()
        pollTimer = Timer.scheduledTimer(
            timeInterval: 0.35,
            target: self,
            selector: #selector(handlePollTick),
            userInfo: nil,
            repeats: true
        )
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func noteCurrentWindow() {
        guard let currentWindow = focusedWindowProvider() else {
            return
        }

        promote([currentWindow])
    }

    func recordSwitcherTransition(from sourceWindow: WindowIdentity?, to destinationWindow: WindowIdentity) {
        if let sourceWindow {
            promote([destinationWindow, sourceWindow])
            return
        }

        promote([destinationWindow])
    }

    @objc
    private func handlePollTick() {
        noteCurrentWindow()
    }

    private func promote(_ windows: [WindowIdentity]) {
        for window in windows.reversed() {
            recentWindows.removeAll(where: { $0 == window })
            recentWindows.insert(window, at: 0)
        }

        if recentWindows.count > 100 {
            recentWindows.removeLast(recentWindows.count - 100)
        }
    }
}
