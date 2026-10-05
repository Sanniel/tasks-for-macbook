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
        guard let group = appGroupIdentifier, !group.isEmpty,
              let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: group)
        else {
            throw StoreError(description:
                "App Group container unavailable (AppGroupIdentifier: \(appGroupIdentifier ?? "missing"))")
        }
        return container
            .appending(path: "Library/Application Support/Tasks", directoryHint: .isDirectory)
            .appending(path: databaseFileName)
    }

    /// Opens the shared repository. Call once per process and keep the instance.
    public static func openRepository() throws -> SQLiteTaskRepository {
        try SQLiteTaskRepository(url: databaseURL())
    }
}
