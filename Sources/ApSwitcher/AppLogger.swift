import OSLog

enum AppLogger {
    static let switcher = Logger(subsystem: "dev.cgomez.apswitcher", category: "switcher")
    static let preview = Logger(subsystem: "dev.cgomez.apswitcher", category: "preview")
    static let catalog = Logger(subsystem: "dev.cgomez.apswitcher", category: "catalog")
}
