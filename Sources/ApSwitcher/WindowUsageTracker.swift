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

        recentWindows.removeAll(where: { $0 == currentWindow })
        recentWindows.insert(currentWindow, at: 0)

        if recentWindows.count > 100 {
            recentWindows.removeLast(recentWindows.count - 100)
        }
    }

    @objc
    private func handlePollTick() {
        noteCurrentWindow()
    }
}
