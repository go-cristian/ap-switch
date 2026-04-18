import AppKit
import Combine
import CoreGraphics

@MainActor
struct SwitcherWindow: Identifiable {
    let id: WindowIdentity
    let title: String
    let appName: String
    let icon: NSImage
    let preview: NSImage?
    let isMinimized: Bool
}

@MainActor
struct SwitcherSpaceStats {
    let currentDesktopNumber: Int
    let desktopCount: Int
    let currentDesktopWindowCount: Int
    let totalWindowCount: Int

    static let empty = SwitcherSpaceStats(
        currentDesktopNumber: 1,
        desktopCount: 1,
        currentDesktopWindowCount: 0,
        totalWindowCount: 0
    )
}

@MainActor
final class SwitcherOverlayModel: ObservableObject {
    @Published var windows: [SwitcherWindow] = []
    @Published var selectedIndex = 0
    @Published var isVisible = false
    @Published var stats = SwitcherSpaceStats.empty
    @Published var footerMessage = "Option+Tab y flechas recorren ventanas. Suelta Option o presiona Enter para activar."

    var selectedWindow: SwitcherWindow? {
        guard windows.indices.contains(selectedIndex) else {
            return nil
        }

        return windows[selectedIndex]
    }

    var selectedWindowID: WindowIdentity? {
        selectedWindow?.id
    }
}

@MainActor
final class AppSwitcherController {
    let overlayModel = SwitcherOverlayModel()

    private let catalogService: any WindowCatalogProviding
    private let usageTracker: WindowUsageTracker
    private let previewLoader: (any WindowPreviewLoading)?
    private var activationTargets: [WindowIdentity: WindowActivationTarget] = [:]
    private var snapshotWindowIDs: [WindowIdentity: CGWindowID] = [:]
    private var previewCache: [CGWindowID: NSImage] = [:]
    private var previewTask: Task<Void, Never>?
    private var overlayFailsafeTimer: Timer?
    private let overlayPresenterFactory: @MainActor (SwitcherOverlayModel) -> any OverlayPresenting
    private lazy var overlayPresenter = overlayPresenterFactory(overlayModel)

    init(
        catalogService: any WindowCatalogProviding,
        usageTracker: WindowUsageTracker,
        previewLoader: (any WindowPreviewLoading)? = {
            if #available(macOS 14.0, *) {
                return ScreenCaptureWindowPreviewLoader()
            }
            return nil
        }(),
        overlayPresenterFactory: @escaping @MainActor (SwitcherOverlayModel) -> any OverlayPresenting = { model in
            OverlayWindowController(model: model)
        }
    ) {
        self.catalogService = catalogService
        self.usageTracker = usageTracker
        self.previewLoader = previewLoader
        self.overlayPresenterFactory = overlayPresenterFactory
    }

    var isVisible: Bool {
        overlayModel.isVisible
    }

    func handleOptionTab(backwards: Bool) {
        if overlayModel.isVisible {
            advanceSelection(movingForward: !backwards)
            return
        }

        showSwitcher(selectingBackward: backwards)
    }

    func handleOptionReleased() {
        guard overlayModel.isVisible else {
            return
        }

        commitSelection()
    }

    func handleEscape() {
        hideSwitcher()
    }

    func handleReturn() {
        guard overlayModel.isVisible else {
            return
        }

        commitSelection()
    }

    func handleArrow(movingForward: Bool) {
        guard overlayModel.isVisible else {
            return
        }

        advanceSelection(movingForward: movingForward)
    }

    private func showSwitcher(selectingBackward: Bool) {
        usageTracker.noteCurrentWindow()

        let catalog = catalogService.currentCatalog()
        AppLogger.switcher.info(
            "showSwitcher catalog items=\(catalog.items.count, privacy: .public) screenCaptureAccessGranted=\(catalog.screenCaptureAccessGranted, privacy: .public)"
        )
        guard !catalog.items.isEmpty else {
            NSSound.beep()
            return
        }

        let orderingCandidates = catalogService.orderingCandidates(from: catalog.items)
        let orderedItems = catalog.items.map(\.sessionCandidate)
        guard let session = SwitcherSessionFactory.make(
            candidates: orderedItems,
            stats: catalog.stats,
            orderingCandidates: orderingCandidates,
            recent: usageTracker.recentWindows,
            selectingBackward: selectingBackward,
            previewCache: previewCache,
            screenCaptureAccessGranted: catalog.screenCaptureAccessGranted
        ) else {
            NSSound.beep()
            return
        }
        AppLogger.switcher.info(
            "showSwitcher orderedItems=\(session.windows.count, privacy: .public) selectingBackward=\(selectingBackward, privacy: .public)"
        )

        activationTargets = Dictionary(uniqueKeysWithValues: catalog.items.map { ($0.id, $0.activationTarget) })
        snapshotWindowIDs = Dictionary(uniqueKeysWithValues: catalog.items.compactMap { item in
            guard let windowID = item.snapshotWindowID else {
                return nil
            }

            return (item.id, windowID)
        })
        overlayModel.windows = session.windows
        overlayModel.stats = session.stats
        overlayModel.footerMessage = session.footerMessage
        overlayModel.selectedIndex = session.selectedIndex
        overlayModel.isVisible = true
        resetOverlayFailsafeTimer()
        overlayPresenter.show()
        loadPreviewsIfNeeded(
            for: catalog.items,
            screenCaptureAccessGranted: catalog.screenCaptureAccessGranted
        )
    }

    private func advanceSelection(movingForward: Bool) {
        overlayModel.selectedIndex = WindowSwitchingLogic.nextSelectionIndex(
            currentIndex: overlayModel.selectedIndex,
            count: overlayModel.windows.count,
            movingForward: movingForward
        )
        resetOverlayFailsafeTimer()
    }

    private func commitSelection() {
        guard let selectedWindowID = overlayModel.selectedWindowID,
              let activationTarget = activationTargets[selectedWindowID] else {
            hideSwitcher()
            return
        }

        hideSwitcher()
        catalogService.activate(activationTarget)
    }

    private func hideSwitcher() {
        AppLogger.switcher.info("hideSwitcher")
        previewTask?.cancel()
        previewTask = nil
        overlayFailsafeTimer?.invalidate()
        overlayFailsafeTimer = nil
        overlayModel.isVisible = false
        overlayPresenter.hide()
        overlayModel.windows.removeAll()
        overlayModel.selectedIndex = 0
        overlayModel.stats = .empty
        overlayModel.footerMessage = SwitcherFooterMessageResolver.normalHint
        activationTargets.removeAll()
        snapshotWindowIDs.removeAll()
    }

    private func resetOverlayFailsafeTimer() {
        overlayFailsafeTimer?.invalidate()
        overlayFailsafeTimer = Timer.scheduledTimer(
            timeInterval: 8,
            target: self,
            selector: #selector(handleOverlayFailsafeTimer),
            userInfo: nil,
            repeats: false
        )
    }

    @objc
    private func handleOverlayFailsafeTimer() {
        hideSwitcher()
    }

    private func loadPreviewsIfNeeded(
        for items: [WindowCatalogItem],
        screenCaptureAccessGranted: Bool
    ) {
        previewTask?.cancel()
        previewTask = nil

        guard screenCaptureAccessGranted else {
            AppLogger.preview.error("loadPreviewsIfNeeded skipped because Screen Recording is not granted")
            return
        }

        guard #available(macOS 14.0, *) else {
            AppLogger.preview.error("loadPreviewsIfNeeded skipped because macOS 14 is required")
            overlayModel.footerMessage = "Las miniaturas requieren macOS 14 o superior."
            return
        }

        guard let previewLoader else {
            AppLogger.preview.error("loadPreviewsIfNeeded skipped because no preview loader is configured")
            overlayModel.footerMessage = SwitcherFooterMessageResolver.missingPreviews
            return
        }

        let uncachedWindowIDs = items.compactMap(\.snapshotWindowID).filter { self.previewCache[$0] == nil }
        AppLogger.preview.info(
            "loadPreviewsIfNeeded requested=\(items.count, privacy: .public) uncached=\(uncachedWindowIDs.count, privacy: .public) cached=\(self.previewCache.count, privacy: .public)"
        )
        if uncachedWindowIDs.isEmpty {
            if overlayModel.windows.contains(where: { $0.preview != nil }) {
                overlayModel.footerMessage = SwitcherFooterMessageResolver.normalHint
            }
            AppLogger.preview.info("loadPreviewsIfNeeded found no uncached windows")
            return
        }

        overlayModel.footerMessage = "Cargando miniaturas..."
        let previewLoaderRef = previewLoader

        previewTask = Task { [weak self] in
            guard let self else {
                return
            }

            let images: [CGWindowID: NSImage]
            do {
                images = try await previewLoaderRef.loadImages(
                    for: uncachedWindowIDs,
                    targetSize: CGSize(width: 444, height: 252)
                )
            } catch {
                guard !Task.isCancelled else {
                    AppLogger.preview.info("preview task cancelled after error")
                    return
                }

                AppLogger.preview.error("WindowPreviewProvider failed: \(String(describing: error), privacy: .public)")
                if overlayModel.isVisible {
                    overlayModel.footerMessage = SwitcherFooterMessageResolver.missingPreviews
                }
                return
            }

            guard !Task.isCancelled else {
                AppLogger.preview.info("preview task cancelled before applying images")
                return
            }

            AppLogger.preview.info(
                "preview load completed images=\(images.count, privacy: .public)"
            )
            for (windowID, image) in images {
                previewCache[windowID] = image
            }

            guard overlayModel.isVisible else {
                return
            }

            overlayModel.windows = overlayModel.windows.map { window in
                guard let snapshotWindowID = snapshotWindowIDs[window.id],
                      let image = previewCache[snapshotWindowID] else {
                    return window
                }

                return SwitcherWindow(
                    id: window.id,
                    title: window.title,
                    appName: window.appName,
                    icon: window.icon,
                    preview: image,
                    isMinimized: window.isMinimized
                )
            }

            overlayModel.footerMessage = SwitcherFooterMessageResolver.resolve(
                screenCaptureAccessGranted: true,
                windows: overlayModel.windows
            )
            AppLogger.preview.info(
                "overlay updated previewsPresent=\(self.overlayModel.windows.contains(where: { $0.preview != nil }), privacy: .public)"
            )
        }
    }
}
