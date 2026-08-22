import OSLog

enum Log {
    static let audio = Logger(subsystem: "com.micahcrandell.mumble", category: "audio")
    static let speech = Logger(subsystem: "com.micahcrandell.mumble", category: "speech")
    static let hotkey = Logger(subsystem: "com.micahcrandell.mumble", category: "hotkey")
    static let inject = Logger(subsystem: "com.micahcrandell.mumble", category: "inject")
    static let app = Logger(subsystem: "com.micahcrandell.mumble", category: "app")
}
