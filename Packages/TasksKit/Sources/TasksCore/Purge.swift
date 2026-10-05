import Foundation

/// Permanent deletion of old completed and archived records.
///
/// - Completed tasks are purged `Retention.purgeAfterDays` after completedAt.
/// - Archived tasks and areas are purged `Retention.purgeAfterDays` after archivedAt.
///   A task that is both completed and archived is kept until the later of the two
///   dates has passed.
/// - Purging an area also purges all its tasks, including completed ones (done by
///   the repository). Subtasks go with their task.
/// - Every purged area/task leaves a tombstone; tombstones are pruned after
///   `Retention.tombstoneDays`.
///
/// Run on app launch and once a day.
public enum Retention {
    /// Days a completed or archived item is kept before it is permanently deleted.
    public static let purgeAfterDays = 30
    /// Days a tombstone is kept for future sync.
    public static let tombstoneDays = 90

    /// When a record completed/archived at `date` gets purged.
    public static func purgeDate(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: purgeAfterDays, to: date)!
    }

    /// Calendar days left before purge, for the Done and Archive views
    /// (30 on the day it was archived, 0 on the day it will be purged).
    public static func daysUntilPurge(
        after date: Date, now: Date, calendar: Calendar = .current
    ) -> Int {
        let purgeDay = LocalDate(purgeDate(after: date, calendar: calendar), calendar: calendar)
        return max(0, LocalDate(now, calendar: calendar).days(until: purgeDay))
    }

    /// The date retention counts from for a task: the later of completedAt and
    /// archivedAt, or nil for an open task.
    public static func retentionStart(of task: TaskItem) -> Date? {
        [task.completedAt, task.archivedAt].compactMap { $0 }.max()
    }
}

public enum Purge {
    /// What to purge as of `now`.
    public static func plan(
        areas: [Area], tasks: [TaskItem], now: Date, calendar: Calendar = .current
    ) -> ChangeSet {
        func expired(_ date: Date) -> Bool {
            Retention.purgeDate(after: date, calendar: calendar) <= now
        }
        let purgedAreas = areas.filter { $0.archivedAt.map(expired) ?? false }.map(\.id)
        let purgedAreaSet = Set(purgedAreas)
        let purgedTasks = tasks
            .filter { !purgedAreaSet.contains($0.areaID) }  // purged with their area
            .filter { Retention.retentionStart(of: $0).map(expired) ?? false }
            .map(\.id)
        return ChangeSet(purgedAreaIDs: purgedAreas, purgedTaskIDs: purgedTasks)
    }

    /// Purges expired records and prunes old tombstones. Returns what was purged.
    @discardableResult
    public static func run(
        on repository: any TaskRepository, now: Date = Date(), calendar: Calendar = .current
    ) throws -> ChangeSet {
        let changes = plan(
            areas: try repository.fetchAreas(includeArchived: true),
            tasks: try repository.fetchTasks(TaskQuery(status: .all)),
            now: now, calendar: calendar)
        try repository.apply(changes, at: now)
        let cutoff = calendar.date(byAdding: .day, value: -Retention.tombstoneDays, to: now)!
        try repository.pruneTombstones(before: cutoff)
        return changes
    }
}
