import CoreGraphics
import Testing
@testable import ApSwitcher

@MainActor
struct WindowUsageTrackerTests {
    @Test func noteCurrentWindowPrependsNewestWindow() {
        var focusedWindow = makeWindow(title: "Editor")
        let tracker = WindowUsageTracker { focusedWindow }

        tracker.noteCurrentWindow()
        focusedWindow = makeWindow(title: "Browser")
        tracker.noteCurrentWindow()

        #expect(tracker.recentWindows.map(\.title) == ["Browser", "Editor"])
    }

    @Test func noteCurrentWindowDeduplicatesCurrentWindow() {
        let currentWindow = makeWindow(title: "Editor")
        let tracker = WindowUsageTracker { currentWindow }

        tracker.noteCurrentWindow()
        tracker.noteCurrentWindow()

        #expect(tracker.recentWindows == [currentWindow])
    }

    @Test func noteCurrentWindowIgnoresNilProviderValues() {
        let tracker = WindowUsageTracker { nil }

        tracker.noteCurrentWindow()

        #expect(tracker.recentWindows.isEmpty)
    }

    @Test func noteCurrentWindowCapsHistoryAtOneHundredWindows() {
        var index = 0
        let tracker = WindowUsageTracker {
            defer { index += 1 }
            return makeWindow(title: "Window \(index)", x: index)
        }

        for _ in 0..<105 {
            tracker.noteCurrentWindow()
        }

        #expect(tracker.recentWindows.count == 100)
        #expect(tracker.recentWindows.first?.title == "Window 104")
        #expect(tracker.recentWindows.last?.title == "Window 5")
    }

    @Test func recordSwitcherTransitionKeepsDestinationThenSourceAtFront() {
        let source = makeWindow(title: "Editor", x: 0)
        let destination = makeWindow(title: "Browser", x: 1)
        let older = makeWindow(title: "Terminal", x: 2)
        let tracker = WindowUsageTracker { source }

        tracker.noteCurrentWindow()
        tracker.recordSwitcherTransition(from: nil, to: older)
        tracker.recordSwitcherTransition(from: source, to: destination)

        #expect(tracker.recentWindows == [destination, source, older])
    }

    @Test func recordSwitcherTransitionDeduplicatesExistingWindows() {
        let source = makeWindow(title: "Editor", x: 0)
        let destination = makeWindow(title: "Browser", x: 1)
        let tracker = WindowUsageTracker { source }

        tracker.recordSwitcherTransition(from: nil, to: destination)
        tracker.recordSwitcherTransition(from: source, to: destination)

        #expect(tracker.recentWindows == [destination, source])
    }

    private func makeWindow(title: String, x: Int = 0) -> WindowIdentity {
        WindowIdentity(
            appPID: 1,
            title: title,
            frame: WindowFrame(CGRect(x: x, y: 0, width: 100, height: 100)),
            ordinal: x
        )
    }
}
