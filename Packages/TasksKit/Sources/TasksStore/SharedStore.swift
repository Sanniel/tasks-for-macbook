import Foundation
import TasksCore

/// Locates the database shared by the app and the widget.
///
/// The App Group id comes from the `AppGroupIdentifier` key in the host bundle's
/// Info.plist, which the build sets to `$(TeamIdentifierPrefix)fi.sannier.tasks`
/// (see Config/Shared.xcconfig), so both targets always agree with their entitlements.
public enum SharedStore {
    public static let databaseFileName = "tasks.sqlite"

    public static var appGroupIdentifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
    }

    /// `<group container>/Library/Application Support/Tasks/tasks.sqlite`
    public static func databaseURL() throws -> URL {
        try directoryURL().appending(path: databaseFileName)
    }

    private static func directoryURL() throws -> URL {
        guard let group = appGroupIdentifier, !group.isEmpty,
              let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: group)
        else {
            throw StoreError(description:
                "App Group container unavailable (AppGroupIdentifier: \(appGroupIdentifier ?? "missing"))")
        }
        return container
            .appending(path: "Library/Application Support/Tasks", directoryHint: .isDirectory)
    }

    /// Opens the shared repository. Call once per process and keep the instance.
    public static func openRepository() throws -> SQLiteTaskRepository {
        try SQLiteTaskRepository(url: databaseURL())
    }

    // MARK: Screenshot mode

    // The app launched with `-screenshots` writes sample data to a separate database
    // and the widget shows that instead of the real one until the expiry date in the
    // marker file. The app removes both on quit; the expiry covers a crash.

    static let demoDatabaseFileName = "demo.sqlite"
    static let demoMarkerFileName = "demo-until"

    public static func demoDatabaseURL() throws -> URL {
        try directoryURL().appending(path: demoDatabaseFileName)
    }

    /// When the widget stops showing the demo database, or nil if it isn't active.
    public static func demoExpiry() -> Date? {
        guard let url = try? directoryURL().appending(path: demoMarkerFileName),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let expiry = try? Date(text.trimmingCharacters(in: .whitespacesAndNewlines), strategy: .iso8601),
              expiry > Date()
        else { return nil }
        return expiry
    }

    /// Starts screenshot mode with a fresh, empty demo database.
    public static func startDemo(until expiry: Date) throws -> SQLiteTaskRepository {
        endDemo()
        let repository = try SQLiteTaskRepository(url: demoDatabaseURL())
        try expiry.formatted(.iso8601).write(
            to: directoryURL().appending(path: demoMarkerFileName), atomically: true, encoding: .utf8)
        return repository
    }

    /// Removes the marker and the demo database (with its WAL files).
    public static func endDemo() {
        guard let directory = try? directoryURL() else { return }
        let names = [demoMarkerFileName] + ["", "-wal", "-shm"].map { demoDatabaseFileName + $0 }
        for name in names {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }
}
