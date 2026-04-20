import AppKit
import ApplicationServices
import CoreGraphics

typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?

@MainActor
struct WindowCatalog {
    let items: [WindowCatalogItem]
    let stats: SwitcherSpaceStats
    let screenCaptureAccessGranted: Bool
}

@MainActor
struct WindowCatalogItem: Identifiable {
    let id: WindowIdentity
    let title: String
    let appName: String
    let icon: NSImage
    let preview: NSImage?
    let snapshotWindowID: CGWindowID?
    let isMinimized: Bool
    let isOnCurrentDesktop: Bool
    let activationTarget: WindowActivationTarget
}

@MainActor
final class WindowActivationTarget {
    let app: NSRunningApplication
    let window: AXUIElement

    init(app: NSRunningApplication, window: AXUIElement) {
        self.app = app
        self.window = window
    }
}

@MainActor
final class WindowCatalogService {
    func currentCatalog() -> WindowCatalog {
        let screenCaptureAccessGranted = CGPreflightScreenCaptureAccess()
        let currentSpaceSnapshot = currentSpaceSnapshot()
        let currentOnScreenSnapshots = screenCaptureAccessGranted ? currentOnScreenSnapshots() : []
        let allSnapshots = screenCaptureAccessGranted ? allWindowSnapshots() : []
        AppLogger.catalog.info(
            "currentCatalog screenCaptureAccessGranted=\(screenCaptureAccessGranted, privacy: .public) onScreenSnapshots=\(currentOnScreenSnapshots.count, privacy: .public) allSnapshots=\(allSnapshots.count, privacy: .public)"
        )
        let currentOnScreenWindowIDs = Set(currentOnScreenSnapshots.map(\.windowID))
        let runningApps = NSWorkspace.shared.runningApplications.filter { application in
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
            application.activationPolicy == .regular &&
            !application.isTerminated &&
            !(application.localizedName ?? "").isEmpty
        }

        var items: [WindowCatalogItem] = []

        for app in runningApps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            let windows = axWindows(for: axApp)
            var unmatchedOnScreenSnapshots = currentOnScreenSnapshots.filter { $0.ownerPID == app.processIdentifier }
            var unmatchedSnapshots = allSnapshots.filter { $0.ownerPID == app.processIdentifier }

            for (ordinal, window) in windows.enumerated() {
                guard shouldInclude(window: window) else {
                    continue
                }

                let frame = frameForWindow(window)
                let identity = makeIdentity(
                    for: window,
                    appPID: app.processIdentifier,
                    ordinal: ordinal,
                    fallbackFrame: frame
                )
                let title = displayTitle(for: window, appName: app.localizedName ?? "App")
                let isMinimized = boolValue(for: window, attribute: kAXMinimizedAttribute)
                let onScreenSnapshot = matchedSnapshot(
                    for: identity,
                    title: title,
                    appPID: app.processIdentifier,
                    frame: frame,
                    snapshotIndex: unmatchedOnScreenSnapshots
                )
                let snapshot = onScreenSnapshot ?? matchedSnapshot(
                    for: identity,
                    title: title,
                    appPID: app.processIdentifier,
                    frame: frame,
                    snapshotIndex: unmatchedSnapshots
                )
                if let snapshot {
                    unmatchedOnScreenSnapshots.removeAll { $0.windowID == snapshot.windowID }
                    unmatchedSnapshots.removeAll { $0.windowID == snapshot.windowID }
                }
                let isOnCurrentDesktop = snapshot.map { currentOnScreenWindowIDs.contains($0.windowID) } ?? false
                let preview: NSImage? = nil

                items.append(
                    WindowCatalogItem(
                        id: identity,
                        title: title,
                        appName: app.localizedName ?? "App",
                        icon: app.icon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: title) ?? NSImage(),
                        preview: preview,
                        snapshotWindowID: snapshot?.windowID,
                        isMinimized: isMinimized,
                        isOnCurrentDesktop: isOnCurrentDesktop,
                        activationTarget: WindowActivationTarget(app: app, window: window)
                    )
                )
            }
        }

        let stats = SwitcherSpaceStats(
            currentDesktopNumber: currentSpaceSnapshot.desktopNumber,
            desktopCount: max(currentSpaceSnapshot.desktopCount, 1),
            currentDesktopWindowCount: items.filter(\.isOnCurrentDesktop).count,
            totalWindowCount: items.count
        )
        AppLogger.catalog.info(
            "currentCatalog returning items=\(items.count, privacy: .public) currentDesktopWindowCount=\(stats.currentDesktopWindowCount, privacy: .public)"
        )

        return WindowCatalog(
            items: items,
            stats: stats,
            screenCaptureAccessGranted: screenCaptureAccessGranted
        )
    }

    func focusedWindowIdentity() -> WindowIdentity? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let focusedWindow = axWindow(for: axApp, attribute: kAXFocusedWindowAttribute) else {
            return nil
        }

        let windows = axWindows(for: axApp)
        let ordinal = windows.firstIndex(where: { CFEqual($0, focusedWindow) }) ?? 0
        let frame = frameForWindow(focusedWindow)
        return makeIdentity(
            for: focusedWindow,
            appPID: app.processIdentifier,
            ordinal: ordinal,
            fallbackFrame: frame
        )
    }

    func activate(_ target: WindowActivationTarget) {
        let app = target.app
        let window = target.window
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        if boolValue(for: window, attribute: kAXMinimizedAttribute) {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    func orderingCandidates(from items: [WindowCatalogItem]) -> [WindowOrderingCandidate] {
        let snapshotIndex = CGPreflightScreenCaptureAccess() ? currentOnScreenSnapshots() : []
        AppLogger.catalog.info(
            "orderingCandidates items=\(items.count, privacy: .public) snapshotIndex=\(snapshotIndex.count, privacy: .public)"
        )
        return items.enumerated().map { offset, item in
            let fallbackIndex = snapshotIndex.first(where: { $0.windowID == item.snapshotWindowID })?.order ?? (10_000 + offset)

            return WindowOrderingCandidate(
                identity: item.id,
                fallbackIndex: fallbackIndex,
                isMinimized: item.isMinimized
            )
        }
    }

    private func shouldInclude(window: AXUIElement) -> Bool {
        if let role = stringValue(for: window, attribute: kAXRoleAttribute), role != (kAXWindowRole as String) {
            return false
        }

        if let subrole = stringValue(for: window, attribute: kAXSubroleAttribute) {
            let allowedSubroles = [
                kAXStandardWindowSubrole as String,
                kAXDialogSubrole as String,
                kAXSystemDialogSubrole as String
            ]

            if !allowedSubroles.contains(subrole) {
                return false
            }
        }

        let frame = frameForWindow(window)
        let isMinimized = boolValue(for: window, attribute: kAXMinimizedAttribute)
        if !isMinimized && (frame.width < 120 || frame.height < 80) {
            return false
        }

        return true
    }

    private func displayTitle(for window: AXUIElement, appName: String) -> String {
        if let title = stringValue(for: window, attribute: kAXTitleAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }

        return appName
    }

    private func axWindows(for app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return []
        }

        return windows
    }

    private func axWindow(for element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func stringValue(for element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? String
    }

    private func boolValue(for element: AXUIElement, attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let boolValue = value as? Bool else {
            return false
        }

        return boolValue
    }

    private func frameForWindow(_ window: AXUIElement) -> CGRect {
        let position = pointValue(for: window, attribute: kAXPositionAttribute) ?? .zero
        let size = sizeValue(for: window, attribute: kAXSizeAttribute) ?? .zero
        return CGRect(origin: position, size: size)
    }

    private func pointValue(for element: AXUIElement, attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func sizeValue(for element: AXUIElement, attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func makeIdentity(
        for window: AXUIElement,
        appPID: pid_t,
        ordinal: Int,
        fallbackFrame: CGRect
    ) -> WindowIdentity {
        let title = stringValue(for: window, attribute: kAXTitleAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let frame = WindowFrame(fallbackFrame)
        return WindowIdentity(appPID: appPID, title: title, frame: frame, ordinal: ordinal)
    }

    private func currentOnScreenSnapshots() -> [WindowSnapshot] {
        windowSnapshots(options: [.optionOnScreenOnly, .excludeDesktopElements])
    }

    private func allWindowSnapshots() -> [WindowSnapshot] {
        windowSnapshots(options: [.optionAll, .excludeDesktopElements])
    }

    private func windowSnapshots(options: CGWindowListOption) -> [WindowSnapshot] {
        guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return rawList.enumerated().compactMap { order, info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
                return nil
            }

            let title = (info[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return WindowSnapshot(
                order: order,
                ownerPID: ownerPID,
                windowID: windowID,
                title: title,
                frame: WindowFrame(bounds)
            )
        }
    }

    private func matchedSnapshot(
        for identity: WindowIdentity,
        title: String,
        appPID: pid_t,
        frame: CGRect,
        snapshotIndex: [WindowSnapshot]
    ) -> WindowSnapshot? {
        let normalizedFrame = WindowFrame(frame)

        if let exactTitleMatch = snapshotIndex.first(where: {
            $0.ownerPID == appPID &&
            $0.frame == normalizedFrame &&
            !$0.title.isEmpty &&
            $0.title == title
        }) {
            return exactTitleMatch
        }

        if let emptyTitleMatch = snapshotIndex.first(where: {
            $0.ownerPID == appPID &&
            $0.frame == normalizedFrame
        }) {
            return emptyTitleMatch
        }

        return snapshotIndex.first(where: { $0.ownerPID == identity.appPID && $0.title == identity.title })
    }
    private func currentSpaceSnapshot() -> CurrentSpaceSnapshot {
        let connection = CGSMainConnectionID()

        guard let rawDisplays = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            return CurrentSpaceSnapshot(
                desktopNumber: 1,
                desktopCount: 1
            )
        }

        var orderedUserSpaces: [CGSSpaceID] = []
        var currentSpaceID: CGSSpaceID?
        for display in rawDisplays {
            if let currentSpace = display["Current Space"] as? [String: Any],
               let id = currentSpace["id64"] as? CGSSpaceID {
                currentSpaceID = id
            }

            guard let spaces = display["Spaces"] as? [[String: Any]] else {
                continue
            }

            for space in spaces {
                guard let type = space["type"] as? Int,
                      type == 0,
                      let id = space["id64"] as? CGSSpaceID,
                      !orderedUserSpaces.contains(id) else {
                    continue
                }

                orderedUserSpaces.append(id)
            }
        }

        let desktopCount = max(orderedUserSpaces.count, 1)
        let activeSpaceID = currentSpaceID ?? orderedUserSpaces.first ?? 1
        let desktopNumber = (orderedUserSpaces.firstIndex(of: activeSpaceID) ?? 0) + 1

        return CurrentSpaceSnapshot(
            desktopNumber: desktopNumber,
            desktopCount: desktopCount
        )
    }
}

private struct WindowSnapshot {
    let order: Int
    let ownerPID: pid_t
    let windowID: CGWindowID
    let title: String
    let frame: WindowFrame
}

private struct CurrentSpaceSnapshot {
    let desktopNumber: Int
    let desktopCount: Int
}
