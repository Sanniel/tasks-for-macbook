import Foundation

/// Which tasks a query returns, by lifecycle state.
public enum TaskStatus: Sendable {
    /// Not completed and not archived.
    case open
    /// Completed and not archived.
    case completed
    /// Archived (whether or not completed).
    case archived
    case all
}

public struct TaskQuery: Sendable {
    public var status: TaskStatus
    /// nil = all areas.
    public var areaID: UUID?

    public init(status: TaskStatus = .open, areaID: UUID? = nil) {
        self.status = status
        self.areaID = areaID
    }
}

/// A set of writes applied atomically.
///
/// Upserts are applied first, then deletes. Deletes are permanent (purge) and
/// leave a tombstone; normal "delete" in the UI is archiving, i.e. an upsert
/// with `archivedAt` set.
public struct ChangeSet: Sendable {
    public var areas: [Area] = []
    public var tasks: [TaskItem] = []
    public var subtasks: [Subtask] = []
    /// Purging an area also purges all of its tasks (and their subtasks).
    public var purgedAreaIDs: [UUID] = []
    /// Purging a task also purges its subtasks.
    public var purgedTaskIDs: [UUID] = []
    public var purgedSubtaskIDs: [UUID] = []
    /// Tombstones to record as-is (e.g. from an import). Unlike purges, these
    /// delete nothing; they only keep the record of deletes for future sync.
    public var tombstones: [Tombstone] = []

    public init(
        areas: [Area] = [], tasks: [TaskItem] = [], subtasks: [Subtask] = [],
        purgedAreaIDs: [UUID] = [], purgedTaskIDs: [UUID] = [], purgedSubtaskIDs: [UUID] = [],
        tombstones: [Tombstone] = []
    ) {
        self.areas = areas
        self.tasks = tasks
        self.subtasks = subtasks
        self.purgedAreaIDs = purgedAreaIDs
        self.purgedTaskIDs = purgedTaskIDs
        self.purgedSubtaskIDs = purgedSubtaskIDs
        self.tombstones = tombstones
    }

    public var isEmpty: Bool {
        areas.isEmpty && tasks.isEmpty && subtasks.isEmpty
            && purgedAreaIDs.isEmpty && purgedTaskIDs.isEmpty && purgedSubtaskIDs.isEmpty
            && tombstones.isEmpty
    }
}

/// Storage for all task data. The UI and business logic depend only on this
/// protocol, never on the storage engine.
///
/// Fetches return records in storage order unless stated otherwise; sorting by
/// effective priority etc. is business logic and lives in TasksCore.
public protocol TaskRepository: Sendable {
    /// Areas ordered by `sortOrder`.
    func fetchAreas(includeArchived: Bool) throws -> [Area]
    func fetchArea(id: UUID) throws -> Area?

    func fetchTasks(_ query: TaskQuery) throws -> [TaskItem]
    func fetchTask(id: UUID) throws -> TaskItem?

    /// Subtasks of the given tasks (all subtasks if `taskIDs` is nil), ordered by `sortOrder`.
    func fetchSubtasks(taskIDs: [UUID]?) throws -> [Subtask]

    func fetchTombstones() throws -> [Tombstone]

    /// Applies all changes in one transaction. Purged records get tombstones dated `date`.
    func apply(_ changes: ChangeSet, at date: Date) throws

    /// Deletes tombstones older than `date`.
    func pruneTombstones(before date: Date) throws
}

extension TaskRepository {
    public func apply(_ changes: ChangeSet) throws {
        try apply(changes, at: Date())
    }

    public func save(_ area: Area) throws {
        try apply(ChangeSet(areas: [area]))
    }

    public func save(_ task: TaskItem) throws {
        try apply(ChangeSet(tasks: [task]))
    }

    public func save(_ subtask: Subtask) throws {
        try apply(ChangeSet(subtasks: [subtask]))
    }

    public func fetchSubtasks(taskID: UUID) throws -> [Subtask] {
        try fetchSubtasks(taskIDs: [taskID])
    }
}
