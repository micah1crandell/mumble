import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLogin {
    private static let configuredKey = "launchAtLoginConfigured"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(true, forKey: configuredKey)
            return true
        } catch {
            Log.app.error("Could not update launch-at-login: \(error.localizedDescription)")
            return false
        }
    }

    static func enableByDefaultIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: configuredKey) else { return }
        _ = setEnabled(true)
    }
}