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
            previousOccurrenceID: task.id,
            createdAt: now)
        let nextSubtasks = subtasks
            .filter { $0.taskID == task.id }
            .map { Subtask(taskID: next.id, title: $0.title, sortOrder: $0.sortOrder, createdAt: now) }
        return (next, nextSubtasks)
    }

    /// Moves a completed task back to the open list.
    ///
    /// For a recurring task, only one occurrence should be open at a time: if
    /// completing it created a next occurrence that is still open and untouched
    /// (never edited, nor its subtasks: `updatedAt == createdAt`), that successor is
    /// removed. An edited successor is kept, and both stay open.
    ///
    /// `allTasks` is searched for the successor; pass all tasks (any status).
    public static func reopen(_ task: TaskItem, allTasks: [TaskItem], now: Date) -> ChangeSet {
        guard task.completedAt != nil else { return ChangeSet() }
        var t = task
        t.completedAt = nil
        t.updatedAt = now
        var changes = ChangeSet(tasks: [t])
        if let successor = untouchedSuccessor(of: task, in: allTasks) {
            changes.purgedTaskIDs = [successor.id]
        }
        return changes
    }

    /// The open, never-edited occurrence created by completing `task`, if any.
    public static func untouchedSuccessor(of task: TaskItem, in allTasks: [TaskItem]) -> TaskItem? {
        guard task.recurrence != nil else { return nil }
        return allTasks.first {
            $0.previousOccurrenceID == task.id && $0.isOpen && $0.updatedAt == $0.createdAt
        }
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
    ///
    /// If the task's area is archived, the area is restored too so the task is visible
    /// again; the area's other archived tasks stay archived.
    public static func restore(_ task: TaskItem, area: Area?, now: Date) -> ChangeSet {
        guard task.archivedAt != nil else { return ChangeSet() }
        var t = task
        t.archivedAt = nil
        t.archivedWithArea = false
        t.updatedAt = now
        var changes = ChangeSet(tasks: [t])
        if var area, area.id == task.areaID, area.archivedAt != nil {
            area.archivedAt = nil
            area.updatedAt = now
            changes.areas = [area]
        }
        return changes
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

    /// See `TaskActions.reopen`.
    public func reopenTask(id: UUID, now: Date = Date()) throws {
        guard let task = try fetchTask(id: id) else { return }
        try apply(TaskActions.reopen(task, allTasks: try fetchTasks(TaskQuery(status: .open)), now: now), at: now)
    }

    /// See `TaskActions.restore`.
    public func restoreTask(id: UUID, now: Date = Date()) throws {
        guard let task = try fetchTask(id: id) else { return }
        try apply(TaskActions.restore(task, area: try fetchArea(id: task.areaID), now: now), at: now)
    }

    /// See `TaskActions.archiveArea`.
    public func archiveArea(id: UUID, now: Date = Date()) throws {
        guard let area = try fetchArea(id: id) else { return }
        let tasks = try fetchTasks(TaskQuery(status: .open, areaID: id))
        try apply(TaskActions.archiveArea(area, tasks: tasks, now: now), at: now)
    }

    /// See `TaskActions.restoreArea`.
    public func restoreArea(id: UUID, now: Date = Date()) throws {
        guard let area = try fetchArea(id: id) else { return }
        let tasks = try fetchTasks(TaskQuery(status: .archived, areaID: id))
        try apply(TaskActions.restoreArea(area, tasks: tasks, now: now), at: now)
    }
}

extension TaskRepository {
    /// Ticks a checklist item on or off. Also bumps the parent task's `updatedAt`, so
    /// the task counts as edited (see `TaskActions.reopen`). Used by the widget.
    public func setSubtask(id: UUID, done: Bool, now: Date = Date()) throws {
        guard var subtask = try fetchSubtasks(taskIDs: nil).first(where: { $0.id == id }),
              subtask.isDone != done
        else { return }
        subtask.isDone = done
        subtask.updatedAt = now
        var changes = ChangeSet(subtasks: [subtask])
        if var task = try fetchTask(id: subtask.taskID) {
            task.updatedAt = now
            changes.tasks = [task]
        }
        try apply(changes, at: now)
    }
}
