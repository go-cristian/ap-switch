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
    @Published var footerMessage = "Cmd+Tab y flechas recorren ventanas. Suelta Command o presiona Enter para activar."

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

    private struct CachedCatalogSnapshot {
        let catalog: WindowCatalog
        let orderingCandidates: [WindowOrderingCandidate]
        let updatedAt: Date

        var isFresh: Bool {
            Date().timeIntervalSince(updatedAt) <= 1.5
        }
    }

    private let catalogRefreshInterval: TimeInterval = 1.5
    private let previewRefreshInterval: TimeInterval = 5
    private let spaceChangeSettleInterval: TimeInterval = 0.35
    private let overlayReconciliationInterval: TimeInterval = 0.1
    private let previewTargetSize = CGSize(width: 444, height: 252)
    private let catalogService: any WindowCatalogProviding
    private let usageTracker: WindowUsageTracker
    private let previewLoader: (any WindowPreviewLoading)?
    private var activationTargets: [WindowIdentity: WindowActivationTarget] = [:]
    private var snapshotWindowIDs: [WindowIdentity: CGWindowID] = [:]
    private var previewCache: [CGWindowID: NSImage] = [:]
    private var cachedCatalogSnapshot: CachedCatalogSnapshot?
    private var previewTask: Task<Void, Never>?
    private var pendingShowTask: Task<Void, Never>?
    private var overlayReconciliationTask: Task<Void, Never>?
    private var catalogRefreshTimer: Timer?
    private var previewRefreshTimer: Timer?
    private var overlayFailsafeTimer: Timer?
    private var activeSpaceObserver: NSObjectProtocol?
    private var lastActiveSpaceChangeAt = Date.distantPast
    private var sourceWindowBeforeSwitcher: WindowIdentity?
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

        observeActiveSpaceChanges()
        startCatalogRefreshTimer()
        if previewLoader != nil {
            startPreviewRefreshTimer()
        }

        refreshCatalogSnapshot(force: true)
    }

    var isVisible: Bool {
        overlayModel.isVisible
    }

    func handleCommandTab(backwards: Bool) {
        if overlayModel.isVisible {
            advanceSelection(movingForward: !backwards)
            return
        }

        guard !shouldDelayForRecentSpaceChange else {
            scheduleDeferredShow(selectingBackward: backwards)
            return
        }

        showSwitcher(selectingBackward: backwards)
    }

    func handleCommandReleased() {
        if pendingShowTask != nil && !overlayModel.isVisible {
            pendingShowTask?.cancel()
            pendingShowTask = nil
            return
        }

        guard overlayModel.isVisible else {
            return
        }

        commitSelection()
    }

    func handleEscape() {
        pendingShowTask?.cancel()
        pendingShowTask = nil
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
        sourceWindowBeforeSwitcher = usageTracker.recentWindows.first

        let snapshot = currentCatalogSnapshot()
        let catalog = snapshot.catalog
        AppLogger.switcher.info(
            "showSwitcher catalog items=\(catalog.items.count, privacy: .public) screenCaptureAccessGranted=\(catalog.screenCaptureAccessGranted, privacy: .public) usingFreshSnapshot=\(snapshot.isFresh, privacy: .public)"
        )
        guard !catalog.items.isEmpty else {
            NSSound.beep()
            return
        }

        let orderedItems = catalog.items.map(\.sessionCandidate)
        guard let session = SwitcherSessionFactory.make(
            candidates: orderedItems,
            stats: catalog.stats,
            orderingCandidates: snapshot.orderingCandidates,
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
        scheduleOverlayReconciliation()
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

        usageTracker.recordSwitcherTransition(
            from: sourceWindowBeforeSwitcher,
            to: selectedWindowID
        )
        hideSwitcher()
        catalogService.activate(activationTarget)
    }

    private func hideSwitcher() {
        AppLogger.switcher.info("hideSwitcher")
        previewTask?.cancel()
        previewTask = nil
        pendingShowTask?.cancel()
        pendingShowTask = nil
        overlayReconciliationTask?.cancel()
        overlayReconciliationTask = nil
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
        sourceWindowBeforeSwitcher = nil
    }

    private func startCatalogRefreshTimer() {
        catalogRefreshTimer?.invalidate()
        catalogRefreshTimer = Timer.scheduledTimer(
            timeInterval: catalogRefreshInterval,
            target: self,
            selector: #selector(handleCatalogRefreshTimer),
            userInfo: nil,
            repeats: true
        )
    }

    private func observeActiveSpaceChanges() {
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleActiveSpaceChanged()
            }
        }
    }

    private func startPreviewRefreshTimer() {
        previewRefreshTimer?.invalidate()
        previewRefreshTimer = Timer.scheduledTimer(
            timeInterval: previewRefreshInterval,
            target: self,
            selector: #selector(handlePreviewRefreshTimer),
            userInfo: nil,
            repeats: true
        )
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

    @objc
    private func handleCatalogRefreshTimer() {
        guard !overlayModel.isVisible else {
            return
        }

        refreshCatalogSnapshot(force: true)
    }

    @objc
    private func handlePreviewRefreshTimer() {
        refreshPreviewsInBackground()
    }

    private func handleActiveSpaceChanged() {
        AppLogger.switcher.info("active space changed")
        lastActiveSpaceChangeAt = Date()
        cachedCatalogSnapshot = nil
        pendingShowTask?.cancel()
        pendingShowTask = nil

        guard !overlayModel.isVisible else {
            return
        }

        refreshCatalogSnapshot(force: true)
    }

    private var shouldDelayForRecentSpaceChange: Bool {
        Date().timeIntervalSince(lastActiveSpaceChangeAt) < spaceChangeSettleInterval
    }

    private func scheduleDeferredShow(selectingBackward: Bool) {
        pendingShowTask?.cancel()
        let remainingDelay = max(0, spaceChangeSettleInterval - Date().timeIntervalSince(lastActiveSpaceChangeAt))
        AppLogger.switcher.info("delaying showSwitcher after space change by \(remainingDelay, privacy: .public)s")

        pendingShowTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            if remainingDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remainingDelay * 1_000_000_000))
            }

            guard !Task.isCancelled, !self.overlayModel.isVisible else {
                return
            }

            self.pendingShowTask = nil
            self.showSwitcher(selectingBackward: selectingBackward)
        }
    }

    private func scheduleOverlayReconciliation() {
        overlayReconciliationTask?.cancel()
        overlayReconciliationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(nanoseconds: UInt64(overlayReconciliationInterval * 1_000_000_000))

            guard !Task.isCancelled, self.overlayModel.isVisible else {
                return
            }

            let freshSnapshot = self.refreshCatalogSnapshot(force: true)
            guard self.overlayModel.isVisible else {
                return
            }

            self.rebuildVisibleOverlay(using: freshSnapshot)
            self.loadPreviewsIfNeeded(
                for: freshSnapshot.catalog.items,
                screenCaptureAccessGranted: freshSnapshot.catalog.screenCaptureAccessGranted
            )
        }
    }

    private func currentCatalogSnapshot() -> CachedCatalogSnapshot {
        if let cachedCatalogSnapshot {
            return cachedCatalogSnapshot
        }

        return refreshCatalogSnapshot(force: true)
    }

    @discardableResult
    private func refreshCatalogSnapshot(force: Bool) -> CachedCatalogSnapshot {
        if !force, let cachedCatalogSnapshot {
            return cachedCatalogSnapshot
        }

        let catalog = catalogService.currentCatalog()
        let orderingCandidates = catalogService.orderingCandidates(from: catalog.items)
        let snapshot = CachedCatalogSnapshot(
            catalog: catalog,
            orderingCandidates: orderingCandidates,
            updatedAt: Date()
        )
        cachedCatalogSnapshot = snapshot
        AppLogger.switcher.info(
            "refreshCatalogSnapshot items=\(catalog.items.count, privacy: .public) screenCaptureAccessGranted=\(catalog.screenCaptureAccessGranted, privacy: .public)"
        )
        return snapshot
    }

    private func rebuildVisibleOverlay(using snapshot: CachedCatalogSnapshot) {
        guard overlayModel.isVisible else {
            return
        }

        let selectedWindowID = overlayModel.selectedWindowID
        let orderedItems = snapshot.catalog.items.map(\.sessionCandidate)
        guard let session = SwitcherSessionFactory.make(
            candidates: orderedItems,
            stats: snapshot.catalog.stats,
            orderingCandidates: snapshot.orderingCandidates,
            recent: usageTracker.recentWindows,
            selectingBackward: false,
            previewCache: previewCache,
            screenCaptureAccessGranted: snapshot.catalog.screenCaptureAccessGranted
        ) else {
            return
        }

        activationTargets = Dictionary(uniqueKeysWithValues: snapshot.catalog.items.map { ($0.id, $0.activationTarget) })
        snapshotWindowIDs = session.snapshotWindowIDs
        overlayModel.windows = session.windows
        overlayModel.stats = session.stats
        overlayModel.footerMessage = session.footerMessage

        if let selectedWindowID,
           let selectedIndex = overlayModel.windows.firstIndex(where: { $0.id == selectedWindowID }) {
            overlayModel.selectedIndex = selectedIndex
            return
        }

        overlayModel.selectedIndex = min(overlayModel.selectedIndex, max(overlayModel.windows.count - 1, 0))
    }

    private func loadPreviewsIfNeeded(
        for items: [WindowCatalogItem],
        screenCaptureAccessGranted: Bool
    ) {
        requestPreviewLoad(
            for: items.compactMap(\.snapshotWindowID),
            screenCaptureAccessGranted: screenCaptureAccessGranted,
            forceRefresh: false,
            updateVisibleOverlay: true
        )
    }

    private func refreshPreviewsInBackground() {
        guard overlayModel.isVisible else {
            AppLogger.preview.info("refreshPreviewsInBackground skipped because overlay is hidden")
            return
        }

        let screenCaptureAccessGranted = cachedCatalogSnapshot?.catalog.screenCaptureAccessGranted ?? CGPreflightScreenCaptureAccess()
        guard screenCaptureAccessGranted else {
            AppLogger.preview.info("refreshPreviewsInBackground skipped because Screen Recording is not granted")
            return
        }

        requestPreviewLoad(
            for: Array(snapshotWindowIDs.values),
            screenCaptureAccessGranted: screenCaptureAccessGranted,
            forceRefresh: true,
            updateVisibleOverlay: true
        )
    }

    private func requestPreviewLoad(
        for windowIDs: [CGWindowID],
        screenCaptureAccessGranted: Bool,
        forceRefresh: Bool,
        updateVisibleOverlay: Bool
    ) {
        previewTask?.cancel()
        previewTask = nil

        guard screenCaptureAccessGranted else {
            AppLogger.preview.error("loadPreviewsIfNeeded skipped because Screen Recording is not granted")
            return
        }

        guard #available(macOS 14.0, *) else {
            AppLogger.preview.error("loadPreviewsIfNeeded skipped because macOS 14 is required")
            if updateVisibleOverlay {
                overlayModel.footerMessage = "Las miniaturas requieren macOS 14 o superior."
            }
            return
        }

        guard let previewLoader else {
            AppLogger.preview.error("loadPreviewsIfNeeded skipped because no preview loader is configured")
            if updateVisibleOverlay {
                overlayModel.footerMessage = SwitcherFooterMessageResolver.missingPreviews
            }
            return
        }

        let requestedWindowIDs = deduplicatedWindowIDs(from: windowIDs)
        let uncachedWindowIDs = forceRefresh
            ? requestedWindowIDs
            : requestedWindowIDs.filter { self.previewCache[$0] == nil }
        AppLogger.preview.info(
            "requestPreviewLoad requested=\(requestedWindowIDs.count, privacy: .public) loading=\(uncachedWindowIDs.count, privacy: .public) cached=\(self.previewCache.count, privacy: .public) forceRefresh=\(forceRefresh, privacy: .public)"
        )
        if uncachedWindowIDs.isEmpty {
            if updateVisibleOverlay {
                applyCachedPreviewsToOverlay(screenCaptureAccessGranted: true)
            }
            AppLogger.preview.info("requestPreviewLoad found no windows to load")
            return
        }

        if updateVisibleOverlay {
            overlayModel.footerMessage = "Cargando miniaturas..."
        }
        let previewLoaderRef = previewLoader

        previewTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let images: [CGWindowID: NSImage]
            do {
                images = try await previewLoaderRef.loadImages(
                    for: uncachedWindowIDs,
                    targetSize: previewTargetSize
                )
            } catch {
                guard !Task.isCancelled else {
                    AppLogger.preview.info("preview task cancelled after error")
                    return
                }

                AppLogger.preview.error("WindowPreviewProvider failed: \(String(describing: error), privacy: .public)")
                if updateVisibleOverlay && overlayModel.isVisible {
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

            guard updateVisibleOverlay, overlayModel.isVisible else {
                return
            }

            applyCachedPreviewsToOverlay(screenCaptureAccessGranted: true)
        }
    }

    private func applyCachedPreviewsToOverlay(screenCaptureAccessGranted: Bool) {
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
            screenCaptureAccessGranted: screenCaptureAccessGranted,
            windows: overlayModel.windows
        )
        AppLogger.preview.info(
            "overlay updated previewsPresent=\(self.overlayModel.windows.contains(where: { $0.preview != nil }), privacy: .public)"
        )
    }

    private func deduplicatedWindowIDs(from windowIDs: [CGWindowID]) -> [CGWindowID] {
        var seen: Set<CGWindowID> = []
        return windowIDs.filter { seen.insert($0).inserted }
    }
}
