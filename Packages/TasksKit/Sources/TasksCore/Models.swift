import Foundation

// Plain value types shared by the app, the widget and storage. Every record has a
// UUID id plus createdAt/updatedAt so it can be synced later. Callers set
// updatedAt when they change a record; storage persists values as given (so that
// a future sync can apply remote records without rewriting their timestamps).

/// A category a task belongs to, e.g. "Private", "Learning", "Client X".
public struct Area: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    /// `#RRGGBB`
    public var colorHex: String
    /// User-defined order; lower comes first.
    public var sortOrder: Int
    /// Soft delete. Purged 30 days after this date.
    public var archivedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), name: String, colorHex: String, sortOrder: Int,
        archivedAt: Date? = nil, createdAt: Date = Date(), updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// A task. Named `TaskItem` to avoid clashing with Swift Concurrency's `Task`.
public struct TaskItem: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var areaID: UUID
    public var priority: Priority
    public var notes: String?
    /// Date-only. A future start date means "not started yet".
    public var startDate: LocalDate?
    /// Date-only.
    public var dueDate: LocalDate?
    /// Recurring tasks always have a due date and a rule with an end date.
    public var recurrence: RecurrenceRule?
    /// Purged 30 days after this date.
    public var completedAt: Date?
    /// Soft delete. Purged 30 days after this date.
    public var archivedAt: Date?
    /// True when the task was archived as part of archiving its area, so that
    /// restoring the area restores exactly those tasks.
    public var archivedWithArea: Bool
    /// For a generated recurring occurrence: the occurrence whose completion created it.
    /// Used to remove an untouched successor when that occurrence is reopened.
    public var previousOccurrenceID: UUID?
    /// Set on every edit to the task or any of its subtasks.
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), title: String, areaID: UUID, priority: Priority = .normal,
        notes: String? = nil, startDate: LocalDate? = nil, dueDate: LocalDate? = nil,
        recurrence: RecurrenceRule? = nil, completedAt: Date? = nil, archivedAt: Date? = nil,
        archivedWithArea: Bool = false, previousOccurrenceID: UUID? = nil,
        createdAt: Date = Date(), updatedAt: Date? = nil
    ) {
        self.previousOccurrenceID = previousOccurrenceID
        self.id = id
        self.title = title
        self.areaID = areaID
        self.priority = priority
        self.notes = notes
        self.startDate = startDate
        self.dueDate = dueDate
        self.recurrence = recurrence
        self.completedAt = completedAt
        self.archivedAt = archivedAt
        self.archivedWithArea = archivedWithArea
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// A checklist item inside a task. No priority or dates of its own.
public struct Subtask: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var title: String
    public var isDone: Bool
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), taskID: UUID, title: String, isDone: Bool = false, sortOrder: Int,
        createdAt: Date = Date(), updatedAt: Date? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.isDone = isDone
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// Records that a record was permanently deleted, so other devices can learn
/// about the delete once sync exists. Pruned after a while.
public struct Tombstone: Identifiable, Hashable, Codable, Sendable {
    public enum EntityType: String, Codable, Sendable {
        case area, task, subtask
    }

    public var id: UUID
    public var entityType: EntityType
    public var deletedAt: Date

    public init(id: UUID, entityType: EntityType, deletedAt: Date) {
        self.id = id
        self.entityType = entityType
        self.deletedAt = deletedAt
    }
}
