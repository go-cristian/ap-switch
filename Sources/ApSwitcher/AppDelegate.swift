import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let accessibilityPermissionController = AccessibilityPermissionController()
    private let screenRecordingPermissionController = ScreenRecordingPermissionController()
    private let hotkeyMonitor = GlobalHotkeyMonitor()
    private let catalogService = WindowCatalogService()

    private var usageTracker: WindowUsageTracker?
    private var switcherController: AppSwitcherController?
    private var statusBarController: StatusBarController?
    private var permissionPollTimer: Timer?
    private var hasShownAccessibilityPermissionAlert = false
    private var hasShownScreenRecordingPermissionAlert = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let usageTracker = WindowUsageTracker { [weak self] in
            self?.catalogService.focusedWindowIdentity()
        }
        self.usageTracker = usageTracker

        let switcherController = AppSwitcherController(
            catalogService: catalogService,
            usageTracker: usageTracker
        )
        self.switcherController = switcherController
        statusBarController = StatusBarController()

        hotkeyMonitor.isSwitcherVisibleProvider = { [weak switcherController] in
            MainActor.assumeIsolated {
                switcherController?.isVisible ?? false
            }
        }
        hotkeyMonitor.onOptionTab = { [weak self] backwards in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                if !self.accessibilityPermissionController.isTrusted {
                    self.presentAccessibilityPermissionHelpIfNeeded()
                    return
                }

                self.switcherController?.handleOptionTab(backwards: backwards)
            }
        }
        hotkeyMonitor.onOptionReleased = { [weak switcherController] in
            Task { @MainActor in
                switcherController?.handleOptionReleased()
            }
        }
        hotkeyMonitor.onEscape = { [weak switcherController] in
            Task { @MainActor in
                switcherController?.handleEscape()
            }
        }
        hotkeyMonitor.onArrowNavigation = { [weak switcherController] movingForward in
            Task { @MainActor in
                switcherController?.handleArrow(movingForward: movingForward)
            }
        }
        hotkeyMonitor.onReturn = { [weak switcherController] in
            Task { @MainActor in
                switcherController?.handleReturn()
            }
        }
        hotkeyMonitor.onEmergencyQuit = {
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
        }

        refreshRuntimeState()

        if !accessibilityPermissionController.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.presentAccessibilityPermissionHelpIfNeeded()
                }
            }
        }

        if !screenRecordingPermissionController.isGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.requestScreenRecordingAccessIfNeeded()
                }
            }
        }

        permissionPollTimer = Timer.scheduledTimer(
            timeInterval: 1.5,
            target: self,
            selector: #selector(handlePermissionPoll),
            userInfo: nil,
            repeats: true
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionPollTimer?.invalidate()
        hotkeyMonitor.stop()
        usageTracker?.stop()
    }

    @objc
    private func handlePermissionPoll() {
        refreshRuntimeState()
    }

    private func refreshRuntimeState() {
        accessibilityPermissionController.refreshStatus()
        screenRecordingPermissionController.refreshStatus()

        if accessibilityPermissionController.isTrusted {
            hasShownAccessibilityPermissionAlert = false
            hotkeyMonitor.start()
            usageTracker?.start()
        } else {
            hotkeyMonitor.stop()
            usageTracker?.stop()
        }
    }

    private func presentAccessibilityPermissionHelpIfNeeded() {
        accessibilityPermissionController.refreshStatus()
        guard !accessibilityPermissionController.isTrusted, !hasShownAccessibilityPermissionAlert else {
            return
        }

        hasShownAccessibilityPermissionAlert = true
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ApSwitcher necesita permiso de Accessibility"
        alert.informativeText = "Sin ese permiso, Option+Tab no puede capturar teclado global ni enfocar ventanas."
        alert.addButton(withTitle: "Abrir ajustes")
        alert.addButton(withTitle: "Cerrar")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            accessibilityPermissionController.openSettings()
        }
    }

    private func requestScreenRecordingAccessIfNeeded() {
        screenRecordingPermissionController.refreshStatus()
        guard !screenRecordingPermissionController.isGranted else {
            hasShownScreenRecordingPermissionAlert = false
            return
        }

        let granted = screenRecordingPermissionController.requestIfNeeded()
        AppLogger.preview.info("requestScreenRecordingAccessIfNeeded granted=\(granted, privacy: .public)")

        guard !granted else {
            hasShownScreenRecordingPermissionAlert = false
            return
        }

        presentScreenRecordingPermissionHelpIfNeeded()
    }

    private func presentScreenRecordingPermissionHelpIfNeeded() {
        screenRecordingPermissionController.refreshStatus()
        guard !screenRecordingPermissionController.isGranted, !hasShownScreenRecordingPermissionAlert else {
            return
        }

        hasShownScreenRecordingPermissionAlert = true
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ApSwitcher necesita permiso de Screen Recording"
        alert.informativeText = "Sin ese permiso, macOS no permite generar miniaturas de otras ventanas. Si lo activas ahora, reinicia la app despues."
        alert.addButton(withTitle: "Abrir ajustes")
        alert.addButton(withTitle: "Cerrar")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            screenRecordingPermissionController.openSettings()
        }
    }
}
