import OSLog

enum AppLogger {
    static let switcher = Logger(subsystem: "com.iyubinest.apswitcher", category: "switcher")
    static let preview = Logger(subsystem: "com.iyubinest.apswitcher", category: "preview")
    static let catalog = Logger(subsystem: "com.iyubinest.apswitcher", category: "catalog")
}
