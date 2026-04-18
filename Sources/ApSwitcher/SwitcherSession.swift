import AppKit
import CoreGraphics

@MainActor
protocol WindowCatalogProviding {
    func currentCatalog() -> WindowCatalog
    func orderingCandidates(from items: [WindowCatalogItem]) -> [WindowOrderingCandidate]
    func activate(_ target: WindowActivationTarget)
}

extension WindowCatalogService: WindowCatalogProviding {}

@MainActor
protocol WindowPreviewLoading {
    func loadImages(for windowIDs: [CGWindowID], targetSize: CGSize) async throws -> [CGWindowID: NSImage]
}

@MainActor
@available(macOS 14.0, *)
struct ScreenCaptureWindowPreviewLoader: WindowPreviewLoading {
    func loadImages(for windowIDs: [CGWindowID], targetSize: CGSize) async throws -> [CGWindowID: NSImage] {
        try await WindowPreviewProvider.loadImages(for: windowIDs, targetSize: targetSize)
    }
}

@MainActor
protocol OverlayPresenting {
    func show()
    func hide()
}

extension OverlayWindowController: OverlayPresenting {}

@MainActor
struct SwitcherSessionCandidate {
    let id: WindowIdentity
    let title: String
    let appName: String
    let icon: NSImage
    let preview: NSImage?
    let snapshotWindowID: CGWindowID?
    let isMinimized: Bool
}

@MainActor
struct SwitcherSession {
    let windows: [SwitcherWindow]
    let selectedIndex: Int
    let stats: SwitcherSpaceStats
    let footerMessage: String
    let snapshotWindowIDs: [WindowIdentity: CGWindowID]
}

@MainActor
enum SwitcherFooterMessageResolver {
    static let normalHint = "Option+Tab o Cmd+Tab experimental recorren ventanas. Suelta el modificador o presiona Enter para activar."
    static let missingScreenRecording = "Activa Screen Recording para ApSwitcher y reinicia la app para ver miniaturas."
    static let missingPreviews = "Screen Recording esta activo, pero macOS no entrego miniaturas en esta sesion. Reinicia la app."

    static func resolve(
        screenCaptureAccessGranted: Bool,
        windows: [SwitcherWindow]
    ) -> String {
        guard screenCaptureAccessGranted else {
            return missingScreenRecording
        }

        if windows.contains(where: { $0.preview != nil }) {
            return normalHint
        }

        return missingPreviews
    }
}

@MainActor
enum SwitcherSessionFactory {
    static func make(
        candidates: [SwitcherSessionCandidate],
        stats: SwitcherSpaceStats,
        orderingCandidates: [WindowOrderingCandidate],
        recent: [WindowIdentity],
        selectingBackward: Bool,
        previewCache: [CGWindowID: NSImage],
        screenCaptureAccessGranted: Bool
    ) -> SwitcherSession? {
        guard !candidates.isEmpty else {
            return nil
        }

        let orderedIdentities = WindowSwitchingLogic.orderedWindowIdentities(
            from: orderingCandidates,
            recent: recent
        )
        let candidateLookup = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let orderedCandidates = orderedIdentities.compactMap { candidateLookup[$0] }

        guard !orderedCandidates.isEmpty else {
            return nil
        }

        let windows = orderedCandidates.map { candidate in
            SwitcherWindow(
                id: candidate.id,
                title: candidate.title,
                appName: candidate.appName,
                icon: candidate.icon,
                preview: cachedPreview(for: candidate, previewCache: previewCache),
                isMinimized: candidate.isMinimized
            )
        }

        let snapshotWindowIDs: [WindowIdentity: CGWindowID] = Dictionary(uniqueKeysWithValues: orderedCandidates.compactMap { candidate in
            guard let snapshotWindowID = candidate.snapshotWindowID else {
                return nil
            }

            return (candidate.id, snapshotWindowID)
        })

        return SwitcherSession(
            windows: windows,
            selectedIndex: WindowSwitchingLogic.initialSelectionIndex(
                windowCount: windows.count,
                selectingBackward: selectingBackward
            ),
            stats: stats,
            footerMessage: SwitcherFooterMessageResolver.resolve(
                screenCaptureAccessGranted: screenCaptureAccessGranted,
                windows: windows
            ),
            snapshotWindowIDs: snapshotWindowIDs
        )
    }

    private static func cachedPreview(
        for candidate: SwitcherSessionCandidate,
        previewCache: [CGWindowID: NSImage]
    ) -> NSImage? {
        guard let windowID = candidate.snapshotWindowID else {
            return candidate.preview
        }

        return previewCache[windowID] ?? candidate.preview
    }
}

extension WindowCatalogItem {
    var sessionCandidate: SwitcherSessionCandidate {
        SwitcherSessionCandidate(
            id: id,
            title: title,
            appName: appName,
            icon: icon,
            preview: preview,
            snapshotWindowID: snapshotWindowID,
            isMinimized: isMinimized
        )
    }
}
