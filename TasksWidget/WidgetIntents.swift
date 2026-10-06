import AppIntents
import TasksCore
import TasksStore
import WidgetKit

/// The database, opened once per widget-extension process.
enum WidgetStore {
    static let repository: Result<SQLiteTaskRepository, any Error> = Result {
        try SharedStore.openRepository()
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
        try WidgetStore.repository.get().completeTask(id: id)
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
        try WidgetStore.repository.get().fetchAreas(includeArchived: false)
            .map { AreaEntity(id: $0.id.uuidString, name: $0.name) }
    }
}
