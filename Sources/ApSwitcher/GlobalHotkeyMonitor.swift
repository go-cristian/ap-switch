import AppKit

final class GlobalHotkeyMonitor {
    var onOptionTab: ((Bool) -> Void)?
    var onCommandTab: ((Bool) -> Void)?
    var onOptionReleased: (() -> Void)?
    var onCommandReleased: (() -> Void)?
    var onEscape: (() -> Void)?
    var onReturn: (() -> Void)?
    var onArrowNavigation: ((Bool) -> Void)?
    var onEmergencyQuit: (() -> Void)?
    var isSwitcherVisibleProvider: (() -> Bool)?

    private(set) var isRunning = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var optionIsPressed = false
    private var commandIsPressed = false

    func start() {
        guard !isRunning else {
            return
        }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handleEvent(type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        optionIsPressed = false
        commandIsPressed = false

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isRunning = true
    }

    func stop() {
        guard isRunning else {
            return
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        optionIsPressed = false
        commandIsPressed = false
        isRunning = false
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            return handleKeyDown(event)
        case .flagsChanged:
            handleFlagsChanged(event)
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        let switcherVisible = isSwitcherVisibleProvider?() ?? false

        if keyCode == 12 &&
            flags.contains(NSEvent.ModifierFlags.option) &&
            flags.contains(NSEvent.ModifierFlags.control) {
            onEmergencyQuit?()
            return nil
        }

        if keyCode == 48 && flags.contains(NSEvent.ModifierFlags.command) {
            onCommandTab?(flags.contains(NSEvent.ModifierFlags.shift))
            return nil
        }

        if keyCode == 48 && flags.contains(NSEvent.ModifierFlags.option) {
            onOptionTab?(flags.contains(NSEvent.ModifierFlags.shift))
            return nil
        }

        if switcherVisible && keyCode == 53 {
            onEscape?()
            return nil
        }

        if switcherVisible && (keyCode == 124 || keyCode == 125) {
            onArrowNavigation?(true)
            return nil
        }

        if switcherVisible && (keyCode == 123 || keyCode == 126) {
            onArrowNavigation?(false)
            return nil
        }

        if switcherVisible && (keyCode == 36 || keyCode == 76) {
            onReturn?()
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        let optionPressedNow = flags.contains(NSEvent.ModifierFlags.option)
        let commandPressedNow = flags.contains(NSEvent.ModifierFlags.command)

        if optionIsPressed && !optionPressedNow {
            onOptionReleased?()
        }

        if commandIsPressed && !commandPressedNow {
            onCommandReleased?()
        }

        optionIsPressed = optionPressedNow
        commandIsPressed = commandPressedNow
    }
}
