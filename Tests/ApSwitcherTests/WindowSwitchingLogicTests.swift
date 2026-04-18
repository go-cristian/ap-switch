import CoreGraphics
import Testing
@testable import ApSwitcher

struct WindowSwitchingLogicTests {
    @Test func recentWindowsWinOverFallbackOrder() {
        let first = WindowIdentity(appPID: 1, title: "Editor", frame: WindowFrame(CGRect(x: 0, y: 0, width: 100, height: 100)), ordinal: 0)
        let second = WindowIdentity(appPID: 1, title: "Browser", frame: WindowFrame(CGRect(x: 1, y: 1, width: 100, height: 100)), ordinal: 1)
        let third = WindowIdentity(appPID: 2, title: "Terminal", frame: WindowFrame(CGRect(x: 2, y: 2, width: 100, height: 100)), ordinal: 0)

        let ordered = WindowSwitchingLogic.orderedWindowIdentities(
            from: [
                WindowOrderingCandidate(identity: third, fallbackIndex: 0, isMinimized: false),
                WindowOrderingCandidate(identity: first, fallbackIndex: 1, isMinimized: false),
                WindowOrderingCandidate(identity: second, fallbackIndex: 2, isMinimized: false)
            ],
            recent: [first, second]
        )

        #expect(ordered == [first, second, third])
    }

    @Test func visibleWindowsBeatMinimizedWhenRecencyIsEqual() {
        let visible = WindowIdentity(appPID: 1, title: "Visible", frame: WindowFrame(CGRect(x: 0, y: 0, width: 100, height: 100)), ordinal: 0)
        let minimized = WindowIdentity(appPID: 1, title: "Minimized", frame: WindowFrame(CGRect(x: 10, y: 0, width: 100, height: 100)), ordinal: 1)

        let ordered = WindowSwitchingLogic.orderedWindowIdentities(
            from: [
                WindowOrderingCandidate(identity: minimized, fallbackIndex: 0, isMinimized: true),
                WindowOrderingCandidate(identity: visible, fallbackIndex: 1, isMinimized: false)
            ],
            recent: []
        )

        #expect(ordered == [visible, minimized])
    }

    @Test func forwardSelectionStartsOnPreviousWindow() {
        #expect(WindowSwitchingLogic.initialSelectionIndex(windowCount: 4, selectingBackward: false) == 1)
    }

    @Test func backwardSelectionStartsOnLastWindow() {
        #expect(WindowSwitchingLogic.initialSelectionIndex(windowCount: 4, selectingBackward: true) == 3)
    }

    @Test func nextSelectionWrapsAround() {
        #expect(WindowSwitchingLogic.nextSelectionIndex(currentIndex: 2, count: 3, movingForward: true) == 0)
        #expect(WindowSwitchingLogic.nextSelectionIndex(currentIndex: 0, count: 3, movingForward: false) == 2)
    }

    @Test func titleBreaksFinalTieCaseInsensitively() {
        let alpha = WindowIdentity(appPID: 1, title: "alpha", frame: WindowFrame(CGRect(x: 0, y: 0, width: 100, height: 100)), ordinal: 0)
        let beta = WindowIdentity(appPID: 1, title: "Beta", frame: WindowFrame(CGRect(x: 10, y: 0, width: 100, height: 100)), ordinal: 1)

        let ordered = WindowSwitchingLogic.orderedWindowIdentities(
            from: [
                WindowOrderingCandidate(identity: beta, fallbackIndex: 4, isMinimized: false),
                WindowOrderingCandidate(identity: alpha, fallbackIndex: 4, isMinimized: false)
            ],
            recent: []
        )

        #expect(ordered == [alpha, beta])
    }

    @Test func appPIDBreaksTieBeforeTitleWhenFallbackOrderMatches() {
        let highPID = WindowIdentity(appPID: 9, title: "Alpha", frame: WindowFrame(CGRect(x: 0, y: 0, width: 100, height: 100)), ordinal: 0)
        let lowPID = WindowIdentity(appPID: 2, title: "Zulu", frame: WindowFrame(CGRect(x: 10, y: 0, width: 100, height: 100)), ordinal: 0)

        let ordered = WindowSwitchingLogic.orderedWindowIdentities(
            from: [
                WindowOrderingCandidate(identity: highPID, fallbackIndex: 2, isMinimized: false),
                WindowOrderingCandidate(identity: lowPID, fallbackIndex: 2, isMinimized: false)
            ],
            recent: []
        )

        #expect(ordered == [lowPID, highPID])
    }

    @Test func initialSelectionStartsAtZeroWhenThereIsOnlyOneWindow() {
        #expect(WindowSwitchingLogic.initialSelectionIndex(windowCount: 1, selectingBackward: false) == 0)
        #expect(WindowSwitchingLogic.initialSelectionIndex(windowCount: 0, selectingBackward: true) == 0)
    }

    @Test func nextSelectionReturnsZeroWhenThereAreNoWindows() {
        #expect(WindowSwitchingLogic.nextSelectionIndex(currentIndex: 4, count: 0, movingForward: true) == 0)
    }
}
