import AppKit
import CoreGraphics
import Testing
@testable import ApSwitcher

@MainActor
struct SwitcherSessionFactoryTests {
    @Test func makeReturnsNilWhenThereAreNoCandidates() {
        let session = SwitcherSessionFactory.make(
            candidates: [],
            stats: .empty,
            orderingCandidates: [],
            recent: [],
            selectingBackward: false,
            previewCache: [:],
            screenCaptureAccessGranted: true
        )

        #expect(session == nil)
    }

    @Test func makeUsesMRUOrderAndForwardInitialSelection() {
        let first = makeCandidate(title: "Editor", x: 0, ordinal: 0)
        let second = makeCandidate(title: "Browser", x: 10, ordinal: 1)
        let third = makeCandidate(title: "Terminal", x: 20, ordinal: 2)

        let session = SwitcherSessionFactory.make(
            candidates: [third, first, second],
            stats: .empty,
            orderingCandidates: [
                WindowOrderingCandidate(identity: third.id, fallbackIndex: 0, isMinimized: false),
                WindowOrderingCandidate(identity: first.id, fallbackIndex: 1, isMinimized: false),
                WindowOrderingCandidate(identity: second.id, fallbackIndex: 2, isMinimized: false)
            ],
            recent: [first.id, second.id],
            selectingBackward: false,
            previewCache: [:],
            screenCaptureAccessGranted: true
        )

        #expect(session?.windows.map(\.title) == ["Editor", "Browser", "Terminal"])
        #expect(session?.selectedIndex == 1)
    }

    @Test func makeUsesBackwardInitialSelectionWhenRequested() {
        let first = makeCandidate(title: "Editor", x: 0, ordinal: 0)
        let second = makeCandidate(title: "Browser", x: 10, ordinal: 1)

        let session = SwitcherSessionFactory.make(
            candidates: [first, second],
            stats: .empty,
            orderingCandidates: [
                WindowOrderingCandidate(identity: first.id, fallbackIndex: 0, isMinimized: false),
                WindowOrderingCandidate(identity: second.id, fallbackIndex: 1, isMinimized: false)
            ],
            recent: [],
            selectingBackward: true,
            previewCache: [:],
            screenCaptureAccessGranted: true
        )

        #expect(session?.selectedIndex == 1)
    }

    @Test func makeBuildsSnapshotWindowIDIndex() {
        let first = makeCandidate(title: "Editor", x: 0, ordinal: 0, snapshotWindowID: 111)
        let second = makeCandidate(title: "Browser", x: 10, ordinal: 1, snapshotWindowID: nil)

        let session = SwitcherSessionFactory.make(
            candidates: [first, second],
            stats: .empty,
            orderingCandidates: [
                WindowOrderingCandidate(identity: first.id, fallbackIndex: 0, isMinimized: false),
                WindowOrderingCandidate(identity: second.id, fallbackIndex: 1, isMinimized: false)
            ],
            recent: [],
            selectingBackward: false,
            previewCache: [:],
            screenCaptureAccessGranted: true
        )

        #expect(session?.snapshotWindowIDs == [first.id: 111])
    }

    @Test func makeUsesCachedPreviewOverCandidatePreview() {
        let cached = NSImage(size: NSSize(width: 10, height: 10))
        let fallback = NSImage(size: NSSize(width: 20, height: 20))
        let candidate = makeCandidate(
            title: "Editor",
            x: 0,
            ordinal: 0,
            preview: fallback,
            snapshotWindowID: 321
        )

        let session = SwitcherSessionFactory.make(
            candidates: [candidate],
            stats: .empty,
            orderingCandidates: [
                WindowOrderingCandidate(identity: candidate.id, fallbackIndex: 0, isMinimized: false)
            ],
            recent: [],
            selectingBackward: false,
            previewCache: [321: cached],
            screenCaptureAccessGranted: true
        )

        #expect(session?.windows.first?.preview === cached)
    }

    @Test func footerResolverCoversPermissionAndPreviewStates() {
        let noPreviewWindow = SwitcherWindow(
            id: WindowIdentity(appPID: 1, title: "Editor", frame: WindowFrame(CGRect(x: 0, y: 0, width: 100, height: 100)), ordinal: 0),
            title: "Editor",
            appName: "Editor",
            icon: NSImage(),
            preview: nil,
            isMinimized: false
        )
        let previewWindow = SwitcherWindow(
            id: WindowIdentity(appPID: 2, title: "Browser", frame: WindowFrame(CGRect(x: 10, y: 0, width: 100, height: 100)), ordinal: 0),
            title: "Browser",
            appName: "Browser",
            icon: NSImage(),
            preview: NSImage(size: NSSize(width: 10, height: 10)),
            isMinimized: false
        )

        #expect(
            SwitcherFooterMessageResolver.resolve(screenCaptureAccessGranted: false, windows: [noPreviewWindow]) ==
            SwitcherFooterMessageResolver.missingScreenRecording
        )
        #expect(
            SwitcherFooterMessageResolver.resolve(screenCaptureAccessGranted: true, windows: [noPreviewWindow]) ==
            SwitcherFooterMessageResolver.missingPreviews
        )
        #expect(
            SwitcherFooterMessageResolver.resolve(screenCaptureAccessGranted: true, windows: [previewWindow]) ==
            SwitcherFooterMessageResolver.normalHint
        )
    }

    private func makeCandidate(
        title: String,
        x: Int,
        ordinal: Int,
        preview: NSImage? = nil,
        snapshotWindowID: CGWindowID? = nil
    ) -> SwitcherSessionCandidate {
        let id = WindowIdentity(
            appPID: 1,
            title: title,
            frame: WindowFrame(CGRect(x: x, y: 0, width: 100, height: 100)),
            ordinal: ordinal
        )

        return SwitcherSessionCandidate(
            id: id,
            title: title,
            appName: "TestApp",
            icon: NSImage(),
            preview: preview,
            snapshotWindowID: snapshotWindowID,
            isMinimized: false
        )
    }
}
