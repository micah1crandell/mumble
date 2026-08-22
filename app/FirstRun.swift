import AppKit
import Foundation

/// Turns a raw SwiftPM launch into the installed app launch users expect.
enum AppBootstrap {
    @MainActor
    static func relaunchInstalledAppIfNeeded() -> Bool {
        guard Bundle.main.bundleURL.pathExtension != "app" else { return false }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let makefile = root.appendingPathComponent("Makefile")
        guard FileManager.default.fileExists(atPath: makefile.path) else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/make")
        process.arguments = ["install"]
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["MUMBLE_BOOTSTRAP_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        process.environment = environment

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        guard process.terminationStatus == 0 else { return false }
        return NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Mumble.app"))
    }
}
