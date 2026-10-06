import Foundation

/// Cross-process "data changed" signal between the widget and the app, using a
/// Darwin notification (prefixed with the App Group id, as the sandbox expects).
///
/// The widget posts after writing (e.g. completing a task); the app observes and
/// reloads. The app itself refreshes the widget through WidgetCenter instead.
public enum ChangeNotifier {
    static var name: CFString {
        "\(SharedStore.appGroupIdentifier ?? "fi.sannier.tasks").didChange" as CFString
    }

    public static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name), nil, nil, true)
    }

    // Darwin callbacks are C function pointers and can't capture context, so the
    // (single) handler is kept here. Set once at app launch.
    nonisolated(unsafe) private static var handler: (@Sendable () -> Void)?

    /// Calls `handler` (on an arbitrary thread) whenever another process posts.
    public static func observe(_ handler: @escaping @Sendable () -> Void) {
        Self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, _, _, _ in ChangeNotifier.handler?() },
            name, nil, .deliverImmediately)
    }
}
