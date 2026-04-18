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
    private var hasShownAccessibilityPrimer = false
    private var hasShownAccessibilitySettingsHelp = false
    private var hasShownScreenRecordingPrimer = false
    private var hasRequestedAccessibilitySystemPrompt = false
    private var hasRequestedScreenRecordingSystemPrompt = false

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
                    if self.hasRequestedAccessibilitySystemPrompt || self.hasShownAccessibilityPrimer {
                        self.presentAccessibilityPermissionHelpIfNeeded()
                    } else {
                        self.presentAccessibilityPermissionPrimerIfNeeded()
                    }
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor [weak self] in
                self?.presentNextPermissionPrimerIfNeeded()
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
        presentNextPermissionPrimerIfNeeded()
    }

    private func refreshRuntimeState() {
        accessibilityPermissionController.refreshStatus()
        screenRecordingPermissionController.refreshStatus()

        if accessibilityPermissionController.isTrusted {
            hasRequestedAccessibilitySystemPrompt = false
            hasShownAccessibilitySettingsHelp = false
            hotkeyMonitor.start()
            usageTracker?.start()
        } else {
            hotkeyMonitor.stop()
            usageTracker?.stop()
        }

        if screenRecordingPermissionController.isGranted {
            hasRequestedScreenRecordingSystemPrompt = false
        }
    }

    private func presentNextPermissionPrimerIfNeeded() {
        if !accessibilityPermissionController.isTrusted {
            presentAccessibilityPermissionPrimerIfNeeded()
            return
        }

        if !screenRecordingPermissionController.isGranted {
            presentScreenRecordingPermissionPrimerIfNeeded()
        }
    }

    private func presentAccessibilityPermissionPrimerIfNeeded() {
        accessibilityPermissionController.refreshStatus()
        guard !accessibilityPermissionController.isTrusted, !hasShownAccessibilityPrimer else {
            return
        }

        hasShownAccessibilityPrimer = true
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ApSwitcher necesita permiso de Accessibility"
        alert.informativeText = "Presiona Continuar y macOS mostrara el permiso del sistema. Sin ese permiso, Option+Tab no puede capturar teclado global ni enfocar ventanas."
        alert.addButton(withTitle: "Continuar")
        alert.addButton(withTitle: "Mas tarde")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            requestAccessibilityAccessIfNeeded()
        }
    }

    private func presentAccessibilityPermissionHelpIfNeeded() {
        accessibilityPermissionController.refreshStatus()
        guard !accessibilityPermissionController.isTrusted, !hasShownAccessibilitySettingsHelp else {
            return
        }

        hasShownAccessibilitySettingsHelp = true
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ApSwitcher necesita permiso de Accessibility"
        alert.informativeText = "El prompt del sistema ya fue mostrado antes. Si no aceptaste el permiso, ahora debes habilitarlo manualmente en Ajustes."
        alert.addButton(withTitle: "Abrir ajustes")
        alert.addButton(withTitle: "Cerrar")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            accessibilityPermissionController.openSettings()
        }
    }

    private func requestAccessibilityAccessIfNeeded() {
        accessibilityPermissionController.refreshStatus()
        guard !accessibilityPermissionController.isTrusted else {
            hasRequestedAccessibilitySystemPrompt = false
            hasShownAccessibilitySettingsHelp = false
            return
        }

        hasRequestedAccessibilitySystemPrompt = true
        let granted = accessibilityPermissionController.requestIfNeeded()
        AppLogger.switcher.info("requestAccessibilityAccessIfNeeded granted=\(granted, privacy: .public)")
    }

    private func requestScreenRecordingAccessIfNeeded() {
        screenRecordingPermissionController.refreshStatus()
        guard !screenRecordingPermissionController.isGranted else {
            hasRequestedScreenRecordingSystemPrompt = false
            return
        }

        hasRequestedScreenRecordingSystemPrompt = true
        let granted = screenRecordingPermissionController.requestIfNeeded()
        AppLogger.preview.info("requestScreenRecordingAccessIfNeeded granted=\(granted, privacy: .public)")
    }

    private func presentScreenRecordingPermissionPrimerIfNeeded() {
        screenRecordingPermissionController.refreshStatus()
        guard !screenRecordingPermissionController.isGranted, !hasShownScreenRecordingPrimer else {
            return
        }

        hasShownScreenRecordingPrimer = true
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ApSwitcher necesita permiso de Screen Recording"
        alert.informativeText = "Presiona Continuar y macOS mostrara el permiso del sistema. Sin ese permiso, no se pueden generar miniaturas de otras ventanas."
        alert.addButton(withTitle: "Continuar")
        alert.addButton(withTitle: "Mas tarde")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            requestScreenRecordingAccessIfNeeded()
        }
    }
}
