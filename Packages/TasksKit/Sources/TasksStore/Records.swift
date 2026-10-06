import Foundation
import GRDB
import TasksCore

// Database row types. These mirror the TasksCore models column by column and
// convert to/from them, so the domain models never depend on GRDB.

extension UUID {
    /// How ids are stored: lowercase, hyphenated.
    var dbString: String { uuidString.lowercased() }
}

struct StoreError: Error, CustomStringConvertible {
    let description: String
}

private func uuid(_ string: String, _ column: String) throws -> UUID {
    guard let id = UUID(uuidString: string) else {
        throw StoreError(description: "Invalid UUID in \(column): \(string)")
    }
    return id
}

private func localDate(_ string: String?, _ column: String) throws -> LocalDate? {
    guard let string else { return nil }
    guard let date = LocalDate(isoString: string) else {
        throw StoreError(description: "Invalid date in \(column): \(string)")
    }
    return date
}

struct AreaRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "area"

    var id: String
    var name: String
    var colorName: String
    var sortOrder: Int
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(_ area: Area) {
        id = area.id.dbString
        name = area.name
        colorName = area.colorName
        sortOrder = area.sortOrder
        archivedAt = area.archivedAt
        createdAt = area.createdAt
        updatedAt = area.updatedAt
    }

    func model() throws -> Area {
        Area(
            id: try uuid(id, "area.id"), name: name, colorName: colorName, sortOrder: sortOrder,
            archivedAt: archivedAt, createdAt: createdAt, updatedAt: updatedAt)
    }
}

struct TaskRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "task"

    var id: String
    var title: String
    var areaId: String
    var priority: Int
    var notes: String?
    var startDate: String?
    var dueDate: String?
    /// JSON
    var recurrence: String?
    var completedAt: Date?
    var archivedAt: Date?
    var archivedWithArea: Bool
    var previousOccurrenceId: String?
    var createdAt: Date
    var updatedAt: Date

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    init(_ task: TaskItem) throws {
        id = task.id.dbString
        title = task.title
        areaId = task.areaID.dbString
        priority = task.priority.rawValue
        notes = task.notes
        startDate = task.startDate?.isoString
        dueDate = task.dueDate?.isoString
        recurrence = try task.recurrence.map {
            String(decoding: try Self.jsonEncoder.encode($0), as: UTF8.self)
        }
        completedAt = task.completedAt
        archivedAt = task.archivedAt
        archivedWithArea = task.archivedWithArea
        previousOccurrenceId = task.previousOccurrenceID?.dbString
        createdAt = task.createdAt
        updatedAt = task.updatedAt
    }

    func model() throws -> TaskItem {
        guard let priority = Priority(rawValue: priority) else {
            throw StoreError(description: "Invalid priority in task \(id): \(self.priority)")
        }
        return TaskItem(
            id: try uuid(id, "task.id"),
            title: title,
            areaID: try uuid(areaId, "task.areaId"),
            priority: priority,
            notes: notes,
            startDate: try localDate(startDate, "task.startDate"),
            dueDate: try localDate(dueDate, "task.dueDate"),
            recurrence: try recurrence.map {
                try JSONDecoder().decode(RecurrenceRule.self, from: Data($0.utf8))
            },
            completedAt: completedAt,
            archivedAt: archivedAt,
            archivedWithArea: archivedWithArea,
            previousOccurrenceID: try previousOccurrenceId.map { try uuid($0, "task.previousOccurrenceId") },
            createdAt: createdAt,
            updatedAt: updatedAt)
    }
}

struct SubtaskRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "subtask"

    var id: String
    var taskId: String
    var title: String
    var isDone: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(_ subtask: Subtask) {
        id = subtask.id.dbString
        taskId = subtask.taskID.dbString
        title = subtask.title
        isDone = subtask.isDone
        sortOrder = subtask.sortOrder
        createdAt = subtask.createdAt
        updatedAt = subtask.updatedAt
    }

    func model() throws -> Subtask {
        Subtask(
            id: try uuid(id, "subtask.id"), taskID: try uuid(taskId, "subtask.taskId"),
            title: title, isDone: isDone, sortOrder: sortOrder,
            createdAt: createdAt, updatedAt: updatedAt)
    }
}

struct TombstoneRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tombstone"

    var id: String
    var entityType: String
    var deletedAt: Date

    init(id: UUID, entityType: Tombstone.EntityType, deletedAt: Date) {
        self.id = id.dbString
        self.entityType = entityType.rawValue
        self.deletedAt = deletedAt
    }

    func model() throws -> Tombstone {
        guard let type = Tombstone.EntityType(rawValue: entityType) else {
            throw StoreError(description: "Invalid tombstone entity type: \(entityType)")
        }
        return Tombstone(id: try uuid(id, "tombstone.id"), entityType: type, deletedAt: deletedAt)
    }
}
