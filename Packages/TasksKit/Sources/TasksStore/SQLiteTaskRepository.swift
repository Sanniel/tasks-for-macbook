import Foundation
import GRDB
import TasksCore

/// `TaskRepository` backed by SQLite via GRDB.
///
/// The app and the widget each open their own instance on the same file in the
/// App Group container. WAL mode (DatabasePool) lets them read concurrently;
/// writes from the two processes are serialized by SQLite, waiting on the busy
/// timeout rather than failing.
public final class SQLiteTaskRepository: TaskRepository {
    private let dbWriter: any DatabaseWriter

    /// Opens (creating if needed) the database file at `url` and migrates it.
    public convenience init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.busyMode = .timeout(5)
        try self.init(dbWriter: DatabasePool(path: url.path, configuration: config))
    }

    /// An empty in-memory database, for tests and previews.
    public static func inMemory() throws -> SQLiteTaskRepository {
        try SQLiteTaskRepository(dbWriter: DatabaseQueue())
    }

    private init(dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try Schema.migrator.migrate(dbWriter)
    }

    // MARK: Reads

    public func fetchAreas(includeArchived: Bool) throws -> [Area] {
        try dbWriter.read { db in
            var request = AreaRecord.order(Column("sortOrder"), Column("name"))
            if !includeArchived {
                request = request.filter(Column("archivedAt") == nil)
            }
            return try request.fetchAll(db).map { try $0.model() }
        }
    }

    public func fetchArea(id: UUID) throws -> Area? {
        try dbWriter.read { db in
            try AreaRecord.fetchOne(db, key: id.dbString)?.model()
        }
    }

    public func fetchTasks(_ query: TaskQuery) throws -> [TaskItem] {
        try dbWriter.read { db in
            var request = TaskRecord.all()
            let completedAt = Column("completedAt")
            let archivedAt = Column("archivedAt")
            switch query.status {
            case .open: request = request.filter(completedAt == nil && archivedAt == nil)
            case .completed: request = request.filter(completedAt != nil && archivedAt == nil)
            case .archived: request = request.filter(archivedAt != nil)
            case .all: break
            }
            if let areaID = query.areaID {
                request = request.filter(Column("areaId") == areaID.dbString)
            }
            return try request.fetchAll(db).map { try $0.model() }
        }
    }

    public func fetchTask(id: UUID) throws -> TaskItem? {
        try dbWriter.read { db in
            try TaskRecord.fetchOne(db, key: id.dbString)?.model()
        }
    }

    public func fetchSubtasks(taskIDs: [UUID]?) throws -> [Subtask] {
        try dbWriter.read { db in
            var request = SubtaskRecord.order(Column("taskId"), Column("sortOrder"))
            if let taskIDs {
                request = request.filter(taskIDs.map(\.dbString).contains(Column("taskId")))
            }
            return try request.fetchAll(db).map { try $0.model() }
        }
    }

    public func fetchTombstones() throws -> [Tombstone] {
        try dbWriter.read { db in
            try TombstoneRecord.order(Column("deletedAt")).fetchAll(db).map { try $0.model() }
        }
    }

    // MARK: Writes

    public func apply(_ changes: ChangeSet, at date: Date) throws {
        guard !changes.isEmpty else { return }
        try dbWriter.write { db in
            for area in changes.areas { try AreaRecord(area).save(db) }
            for task in changes.tasks { try TaskRecord(task).save(db) }
            for subtask in changes.subtasks { try SubtaskRecord(subtask).save(db) }
            for tombstone in changes.tombstones {
                try TombstoneRecord(id: tombstone.id, entityType: tombstone.entityType, deletedAt: tombstone.deletedAt).save(db)
            }

            for id in changes.purgedSubtaskIDs {
                if try SubtaskRecord.deleteOne(db, key: id.dbString) {
                    try TombstoneRecord(id: id, entityType: .subtask, deletedAt: date).save(db)
                }
            }
            // Subtasks are removed by ON DELETE CASCADE; the task's tombstone covers them.
            for id in changes.purgedTaskIDs {
                if try TaskRecord.deleteOne(db, key: id.dbString) {
                    try TombstoneRecord(id: id, entityType: .task, deletedAt: date).save(db)
                }
            }
            // Tasks are removed by ON DELETE CASCADE, but each gets its own tombstone.
            for id in changes.purgedAreaIDs {
                let taskIDs = try String.fetchAll(
                    db, TaskRecord.select(Column("id")).filter(Column("areaId") == id.dbString))
                if try AreaRecord.deleteOne(db, key: id.dbString) {
                    try TombstoneRecord(id: id, entityType: .area, deletedAt: date).save(db)
                    for taskID in taskIDs.compactMap(UUID.init(uuidString:)) {
                        try TombstoneRecord(id: taskID, entityType: .task, deletedAt: date).save(db)
                    }
                }
            }
        }
    }

    public func pruneTombstones(before date: Date) throws {
        _ = try dbWriter.write { db in
            try TombstoneRecord.filter(Column("deletedAt") < date).deleteAll(db)
        }
    }
}
