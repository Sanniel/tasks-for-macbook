import Foundation

/// JSON export/import of all data: a backup and a future migration path.
///
/// File format (version 2), keys as in the TasksCore models. Version 1 stored area
/// colors as "colorHex"; those files still import (mapped to color names).
///
///     {
///       "format": "fi.sannier.tasks.backup",
///       "version": 2,
///       "exportedAt": "2026-10-06T08:15:30.123Z",
///       "areas":      [ { "id", "name", "colorName", "sortOrder", "archivedAt"?, "createdAt", "updatedAt" } ],
///       "tasks":      [ { "id", "title", "areaID", "priority" (-1…3), "notes"?, "startDate"?, "dueDate"?,
///                         "recurrence"?, "completedAt"?, "archivedAt"?, "archivedWithArea",
///                         "previousOccurrenceID"?, "createdAt", "updatedAt" } ],
///       "subtasks":   [ { "id", "taskID", "title", "isDone", "sortOrder", "createdAt", "updatedAt" } ],
///       "tombstones": [ { "id", "entityType" ("area"|"task"|"subtask"), "deletedAt" } ]
///     }
///
/// Timestamps are ISO 8601 UTC with milliseconds; startDate/dueDate are `YYYY-MM-DD`;
/// recurrence is the `RecurrenceRule` JSON; optional keys are omitted when empty.
public struct BackupDocument: Codable, Equatable, Sendable {
    public static let formatIdentifier = "fi.sannier.tasks.backup"
    public static let currentVersion = 2

    public var format: String
    public var version: Int
    public var exportedAt: Date
    public var areas: [Area]
    public var tasks: [TaskItem]
    public var subtasks: [Subtask]
    public var tombstones: [Tombstone]

    public init(
        exportedAt: Date, areas: [Area], tasks: [TaskItem], subtasks: [Subtask], tombstones: [Tombstone]
    ) {
        format = Self.formatIdentifier
        version = Self.currentVersion
        self.exportedAt = exportedAt
        self.areas = areas
        self.tasks = tasks
        self.subtasks = subtasks
        self.tombstones = tombstones
    }
}

public enum BackupError: Error, Equatable, CustomStringConvertible {
    case notJSON(String)
    case wrongFormat
    case unsupportedVersion(Int)
    case missingArea(taskTitle: String)
    case missingTask(subtaskTitle: String)

    public var description: String {
        switch self {
        case .notJSON(let detail): "The file isn't a valid Tasks backup (\(detail))."
        case .wrongFormat: "The file isn't a Tasks backup."
        case .unsupportedVersion(let v): "The backup is version \(v); this app reads up to version \(BackupDocument.currentVersion). Update the app first."
        case .missingArea(let title): "The task “\(title)” refers to an area that isn't in the backup or in this app."
        case .missingTask(let title): "The checklist item “\(title)” refers to a task that isn't in the backup or in this app."
        }
    }
}

public enum Backup {
    // MARK: Export

    public static func export(from repository: any TaskRepository, now: Date = Date()) throws -> BackupDocument {
        BackupDocument(
            exportedAt: now,
            areas: try repository.fetchAreas(includeArchived: true),
            tasks: try repository.fetchTasks(TaskQuery(status: .all)),
            subtasks: try repository.fetchSubtasks(taskIDs: nil),
            tombstones: try repository.fetchTombstones())
    }

    public static func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFormatter().string(from: date))
        }
        return try encoder.encode(document)
    }

    // MARK: Import

    public static func decode(_ data: Data) throws -> BackupDocument {
        // Check the header first so a wrong file gets a clear message.
        struct Header: Decodable { var format: String?; var version: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else {
            throw BackupError.notJSON("not a JSON object")
        }
        guard header.format == BackupDocument.formatIdentifier else { throw BackupError.wrongFormat }
        guard let version = header.version, version <= BackupDocument.currentVersion else {
            throw BackupError.unsupportedVersion(header.version ?? -1)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = isoFormatter().date(from: string) ?? isoFormatter(fractional: false).date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid timestamp \(string)")
        }
        do {
            return try decoder.decode(BackupDocument.self, from: data)
        } catch let error as DecodingError {
            throw BackupError.notJSON(describe(error))
        }
    }

    /// What a merge import will do.
    public struct MergeSummary: Equatable, Sendable {
        public var added = 0
        public var updated = 0
        public var unchanged = 0

        public init(added: Int = 0, updated: Int = 0, unchanged: Int = 0) {
            self.added = added
            self.updated = updated
            self.unchanged = unchanged
        }

        public var description: String {
            var parts: [String] = []
            if added > 0 { parts.append("\(added) new item\(added == 1 ? "" : "s") will be added") }
            if updated > 0 { parts.append("\(updated) item\(updated == 1 ? "" : "s") will be updated with a newer version") }
            if unchanged > 0 { parts.append("\(unchanged) item\(unchanged == 1 ? " is" : "s are") already up to date") }
            return parts.isEmpty ? "The backup is empty." : parts.joined(separator: ", ") + "."
        }
    }

    /// Merge rules: records are matched by id. A record that doesn't exist here is
    /// added; one that exists is replaced only if the backup's copy has a newer
    /// `updatedAt`. Nothing is deleted. Tombstones not yet known are recorded.
    ///
    /// Throws if a task's area or a checklist item's task exists neither in the
    /// backup nor here (the import would break references).
    public static func mergePlan(
        _ document: BackupDocument, into repository: any TaskRepository
    ) throws -> (changes: ChangeSet, summary: MergeSummary) {
        let existingAreas = Dictionary(
            try repository.fetchAreas(includeArchived: true).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let existingTasks = Dictionary(
            try repository.fetchTasks(TaskQuery(status: .all)).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let existingSubtasks = Dictionary(
            try repository.fetchSubtasks(taskIDs: nil).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let existingTombstones = Set(try repository.fetchTombstones().map(\.id))

        let areaIDs = Set(existingAreas.keys).union(document.areas.map(\.id))
        if let orphan = document.tasks.first(where: { !areaIDs.contains($0.areaID) }) {
            throw BackupError.missingArea(taskTitle: orphan.title)
        }
        let taskIDs = Set(existingTasks.keys).union(document.tasks.map(\.id))
        if let orphan = document.subtasks.first(where: { !taskIDs.contains($0.taskID) }) {
            throw BackupError.missingTask(subtaskTitle: orphan.title)
        }

        var summary = MergeSummary()
        func pick<T>(_ incoming: [T], existing: [UUID: T], id: (T) -> UUID, updatedAt: (T) -> Date) -> [T] {
            incoming.filter { record in
                guard let current = existing[id(record)] else {
                    summary.added += 1
                    return true
                }
                if isNewer(updatedAt(record), than: updatedAt(current)) {
                    summary.updated += 1
                    return true
                }
                summary.unchanged += 1
                return false
            }
        }

        let changes = ChangeSet(
            areas: pick(document.areas, existing: existingAreas, id: \.id, updatedAt: \.updatedAt),
            tasks: pick(document.tasks, existing: existingTasks, id: \.id, updatedAt: \.updatedAt),
            subtasks: pick(document.subtasks, existing: existingSubtasks, id: \.id, updatedAt: \.updatedAt),
            tombstones: document.tombstones.filter { !existingTombstones.contains($0.id) })
        return (changes, summary)
    }

    // MARK: Helpers

    /// Compared at millisecond precision, the precision timestamps are stored and exported with.
    static func isNewer(_ a: Date, than b: Date) -> Bool {
        (a.timeIntervalSince1970 * 1000).rounded() > (b.timeIntervalSince1970 * 1000).rounded()
    }

    private static func isoFormatter(fractional: Bool = true) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let context): return "missing “\(key.stringValue)” at \(path(context))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "\(context.debugDescription) at \(path(context))"
        @unknown default: return "unreadable data"
        }
    }
}
