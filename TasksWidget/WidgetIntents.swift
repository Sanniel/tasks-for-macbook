import AppIntents
import TasksCore
import TasksStore
import WidgetKit

enum WidgetStore {
    /// The real database, opened once per widget-extension process.
    private static let live: Result<SQLiteTaskRepository, any Error> = Result {
        try SharedStore.openRepository()
    }

    /// The real database, or the sample data while the app runs in screenshot mode.
    static func repository() throws -> SQLiteTaskRepository {
        if SharedStore.demoExpiry() != nil {
            return try SQLiteTaskRepository(url: SharedStore.demoDatabaseURL())
        }
        return try live.get()
    }
}

/// Checkbox in the widget. Uses the same completion logic as the app, so a
/// recurring task gets its next occurrence. WidgetKit reloads the widget afterwards.
struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let isDiscoverable = false

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        try WidgetStore.repository().completeTask(id: id)
        ChangeNotifier.post()
        return .result()
    }
}

/// Widget configuration: all tasks, or one area.
struct TaskListConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Task List"
    static let description = IntentDescription("Show all tasks, or the tasks of one area.")

    @Parameter(title: "Area", description: "Leave empty to show all areas.")
    var area: AreaEntity?
}

struct AreaEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Area"
    static let defaultQuery = AreaQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct AreaQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AreaEntity] {
        try activeAreas().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AreaEntity] {
        try activeAreas()
    }

    private func activeAreas() throws -> [AreaEntity] {
        try WidgetStore.repository().fetchAreas(includeArchived: false)
            .map { AreaEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

/// Checkbox for a checklist item in the widget.
struct CompleteSubtaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Checklist Item"
    static let isDiscoverable = false

    @Parameter(title: "Checklist item ID")
    var subtaskID: String

    init() {}

    init(subtaskID: UUID) {
        self.subtaskID = subtaskID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: subtaskID) else { return .result() }
        try WidgetStore.repository().setSubtask(id: id, done: true)
        ChangeNotifier.post()
        return .result()
    }
}
