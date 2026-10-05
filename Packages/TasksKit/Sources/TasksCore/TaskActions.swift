import Foundation

/// State changes on tasks and areas, as pure functions returning a `ChangeSet`
/// for `TaskRepository.apply`. Every changed record gets `updatedAt = now`.
public enum TaskActions {
    /// Marks the task completed. A recurring task with a further occurrence also
    /// gets its next occurrence created (see `nextOccurrence`).
    /// Completing an already-completed task changes nothing, so a double tap (e.g.
    /// from the widget) can never create two successors.
    public static func complete(_ task: TaskItem, subtasks: [Subtask], now: Date) -> ChangeSet {
        guard task.completedAt == nil else { return ChangeSet() }
        var done = task
        done.completedAt = now
        done.updatedAt = now
        var changes = ChangeSet(tasks: [done])
        if let (next, nextSubtasks) = nextOccurrence(of: task, subtasks: subtasks, now: now) {
            changes.tasks.append(next)
            changes.subtasks = nextSubtasks
        }
        return changes
    }

    /// The occurrence that follows `task`, or nil if it isn't recurring or the series
    /// has ended.
    ///
    /// The new task copies title, area, stored priority, notes and recurrence, plus
    /// the subtasks (reset to not done). Its due date is the next pattern date after
    /// the current due date. If the task has a start date, the new start date keeps
    /// the same number of days before the due date.
    public static func nextOccurrence(
        of task: TaskItem, subtasks: [Subtask], now: Date
    ) -> (TaskItem, [Subtask])? {
        guard let rule = task.recurrence, let due = task.dueDate,
              let nextDue = rule.nextOccurrence(after: due)
        else { return nil }
        let next = TaskItem(
            title: task.title,
            areaID: task.areaID,
            priority: task.priority,
            notes: task.notes,
            startDate: task.startDate.map { nextDue.adding(days: -$0.days(until: due)) },
            dueDate: nextDue,
            recurrence: rule,
            createdAt: now)
        let nextSubtasks = subtasks
            .filter { $0.taskID == task.id }
            .map { Subtask(taskID: next.id, title: $0.title, sortOrder: $0.sortOrder, createdAt: now) }
        return (next, nextSubtasks)
    }

    /// Moves a completed task back to the open list.
    public static func reopen(_ task: TaskItem, now: Date) -> ChangeSet {
        guard task.completedAt != nil else { return ChangeSet() }
        var t = task
        t.completedAt = nil
        t.updatedAt = now
        return ChangeSet(tasks: [t])
    }

    /// Soft-deletes a task. Purged 30 days later unless restored.
    public static func archive(_ task: TaskItem, now: Date) -> ChangeSet {
        guard task.archivedAt == nil else { return ChangeSet() }
        var t = task
        t.archivedAt = now
        t.archivedWithArea = false
        t.updatedAt = now
        return ChangeSet(tasks: [t])
    }

    /// Restores an archived task (to Done if it was completed, otherwise to the open list).
    public static func restore(_ task: TaskItem, now: Date) -> ChangeSet {
        guard task.archivedAt != nil else { return ChangeSet() }
        var t = task
        t.archivedAt = nil
        t.archivedWithArea = false
        t.updatedAt = now
        return ChangeSet(tasks: [t])
    }

    /// Archives an area together with its open tasks (flagged `archivedWithArea`).
    /// Completed tasks stay in Done; already-archived tasks are left as they are.
    /// `tasks` may contain any tasks; only the area's open ones are changed.
    public static func archiveArea(_ area: Area, tasks: [TaskItem], now: Date) -> ChangeSet {
        guard area.archivedAt == nil else { return ChangeSet() }
        var a = area
        a.archivedAt = now
        a.updatedAt = now
        let archived = openTasks(in: area, tasks).map { task in
            var t = task
            t.archivedAt = now
            t.archivedWithArea = true
            t.updatedAt = now
            return t
        }
        return ChangeSet(areas: [a], tasks: archived)
    }

    /// The tasks archiving `area` would archive; used for the confirmation prompt.
    public static func openTasks(in area: Area, _ tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { $0.areaID == area.id && $0.isOpen }
    }

    /// Restores an area and exactly the tasks that were archived with it. Tasks that
    /// were archived individually stay archived.
    public static func restoreArea(_ area: Area, tasks: [TaskItem], now: Date) -> ChangeSet {
        guard area.archivedAt != nil else { return ChangeSet() }
        var a = area
        a.archivedAt = nil
        a.updatedAt = now
        let restored = tasks
            .filter { $0.areaID == area.id && $0.archivedAt != nil && $0.archivedWithArea }
            .map { task in
                var t = task
                t.archivedAt = nil
                t.archivedWithArea = false
                t.updatedAt = now
                return t
            }
        return ChangeSet(areas: [a], tasks: restored)
    }
}

extension TaskRepository {
    /// Reads the task fresh from storage and completes it (see `TaskActions.complete`).
    /// Used by the app and the widget's complete button.
    public func completeTask(id: UUID, now: Date = Date()) throws {
        guard let task = try fetchTask(id: id) else { return }
        let changes = TaskActions.complete(task, subtasks: try fetchSubtasks(taskID: id), now: now)
        try apply(changes, at: now)
    }
}
