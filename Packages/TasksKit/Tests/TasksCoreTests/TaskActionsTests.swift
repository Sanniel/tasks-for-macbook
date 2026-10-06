import Foundation
import Testing
@testable import TasksCore

@Suite struct TaskActionsTests {
    let now = instant("2026-10-05")
    let area = Area(name: "Private", colorHex: "#FF0000", sortOrder: 0)

    @Test func completingPlainTask() {
        let task = TaskItem(title: "Call", areaID: area.id, dueDate: d("2026-10-05"))
        let changes = TaskActions.complete(task, subtasks: [], now: now)
        #expect(changes.tasks.count == 1)
        #expect(changes.tasks[0].completedAt == now)
        #expect(changes.tasks[0].updatedAt == now)
    }

    @Test func completingTwiceDoesNothing() {
        var task = TaskItem(
            title: "Gym", areaID: area.id, dueDate: d("2026-10-05"),
            recurrence: RecurrenceRule(pattern: .weekly(weekdays: [.monday]), endDate: d("2027-01-01")))
        task.completedAt = now
        #expect(TaskActions.complete(task, subtasks: [], now: now).isEmpty)
    }

    @Test func completingRecurringCreatesNextOccurrence() throws {
        let rule = RecurrenceRule(pattern: .weekly(weekdays: [.monday, .thursday]), endDate: d("2027-01-01"))
        let task = TaskItem(
            title: "Water plants", areaID: area.id, priority: .raised, notes: "Balcony too",
            startDate: d("2026-10-03"), dueDate: d("2026-10-05"), recurrence: rule)
        let subtasks = [
            Subtask(taskID: task.id, title: "Kitchen", isDone: true, sortOrder: 0),
            Subtask(taskID: task.id, title: "Balcony", isDone: false, sortOrder: 1),
        ]
        // Completed two days late: the next occurrence follows the pattern, not the completion day.
        let changes = TaskActions.complete(task, subtasks: subtasks, now: instant("2026-10-07"))

        #expect(changes.tasks.count == 2)
        let next = try #require(changes.tasks.first { $0.id != task.id })
        #expect(next.title == "Water plants")
        #expect(next.areaID == area.id)
        #expect(next.priority == .raised)
        #expect(next.notes == "Balcony too")
        #expect(next.recurrence == rule)
        #expect(next.dueDate == d("2026-10-08"))
        #expect(next.startDate == d("2026-10-06"))  // same 2-day gap before due
        #expect(next.completedAt == nil)
        #expect(changes.subtasks.map(\.title) == ["Kitchen", "Balcony"])
        #expect(changes.subtasks.allSatisfy { !$0.isDone && $0.taskID == next.id })
        #expect(Set(changes.subtasks.map(\.id)).isDisjoint(with: subtasks.map(\.id)))
    }

    @Test func completingLastOccurrenceEndsSeries() {
        let task = TaskItem(
            title: "Course", areaID: area.id, dueDate: d("2026-10-05"),
            recurrence: RecurrenceRule(pattern: .monthly(days: [5]), endDate: d("2026-11-04")))
        let changes = TaskActions.complete(task, subtasks: [], now: now)
        #expect(changes.tasks.map(\.id) == [task.id])
    }

    @Test func reopen() {
        var task = TaskItem(title: "x", areaID: area.id)
        task.completedAt = now
        let reopened = TaskActions.reopen(task, allTasks: [], now: now).tasks
        #expect(reopened.count == 1 && reopened[0].completedAt == nil)
    }

    @Test func archiveAndRestoreTask() throws {
        let task = TaskItem(title: "x", areaID: area.id)
        let archived = try #require(TaskActions.archive(task, now: now).tasks.first)
        #expect(archived.archivedAt == now && !archived.archivedWithArea)
        let restored = try #require(TaskActions.restore(archived, area: area, now: now).tasks.first)
        #expect(restored.archivedAt == nil)
    }

    @Test func reopeningRecurringRemovesUntouchedSuccessor() throws {
        let rule = RecurrenceRule(pattern: .weekly(weekdays: [.monday]), endDate: d("2027-01-01"))
        let task = TaskItem(title: "Gym", areaID: area.id, dueDate: d("2026-10-05"), recurrence: rule)
        let completion = TaskActions.complete(task, subtasks: [], now: now)
        let done = try #require(completion.tasks.first { $0.id == task.id })
        let successor = try #require(completion.tasks.first { $0.id != task.id })
        #expect(successor.previousOccurrenceID == task.id)

        let reopen = TaskActions.reopen(done, allTasks: [done, successor], now: instant("2026-10-06"))
        #expect(reopen.purgedTaskIDs == [successor.id])
        #expect(reopen.tasks.map(\.completedAt) == [nil])

        // Once the successor (or one of its subtasks) was edited, it is kept.
        var edited = successor
        edited.updatedAt = instant("2026-10-06")
        #expect(TaskActions.reopen(done, allTasks: [done, edited], now: now).purgedTaskIDs.isEmpty)
    }

    @Test func restoringTaskRestoresItsArchivedAreaOnly() throws {
        var archivedArea = area
        archivedArea.archivedAt = now
        var task = TaskItem(title: "x", areaID: area.id)
        task.archivedAt = now
        let changes = TaskActions.restore(task, area: archivedArea, now: now)
        #expect(changes.areas.map(\.archivedAt) == [nil])
        #expect(changes.tasks.map(\.id) == [task.id])
        // Area already active: untouched.
        #expect(TaskActions.restore(task, area: area, now: now).areas.isEmpty)
    }

    @Test func archivingAreaArchivesOnlyItsOpenTasks() {
        let open = TaskItem(title: "open", areaID: area.id)
        var done = TaskItem(title: "done", areaID: area.id)
        done.completedAt = now
        var alreadyArchived = TaskItem(title: "archived earlier", areaID: area.id)
        alreadyArchived.archivedAt = instant("2026-09-01")
        let otherArea = TaskItem(title: "other", areaID: UUID())
        let all = [open, done, alreadyArchived, otherArea]

        #expect(TaskActions.openTasks(in: area, all).map(\.title) == ["open"])
        let changes = TaskActions.archiveArea(area, tasks: all, now: now)
        #expect(changes.areas.map(\.archivedAt) == [now])
        #expect(changes.tasks.map(\.title) == ["open"])
        #expect(changes.tasks.allSatisfy { $0.archivedAt == now && $0.archivedWithArea })
    }

    @Test func restoringAreaRestoresOnlyTasksArchivedWithIt() {
        var archivedArea = area
        archivedArea.archivedAt = now
        var withArea = TaskItem(title: "with area", areaID: area.id)
        withArea.archivedAt = now
        withArea.archivedWithArea = true
        var individually = TaskItem(title: "individually", areaID: area.id)
        individually.archivedAt = instant("2026-09-01")

        let changes = TaskActions.restoreArea(archivedArea, tasks: [withArea, individually], now: now)
        #expect(changes.areas.map(\.archivedAt) == [nil])
        #expect(changes.tasks.map(\.title) == ["with area"])
        #expect(changes.tasks.allSatisfy { $0.archivedAt == nil && !$0.archivedWithArea })
    }

    @Test func validation() {
        var task = TaskItem(title: "  ", areaID: area.id)
        #expect(task.validationErrors == [.emptyTitle])
        task.title = "Ok"
        task.recurrence = RecurrenceRule(pattern: .weekly(weekdays: []), endDate: d("2027-01-01"))
        #expect(task.validationErrors == [.recurrenceWithoutDueDate, .recurrenceWithoutDays])
        task.recurrence = nil
        task.startDate = d("2026-10-10")
        task.dueDate = d("2026-10-09")
        #expect(task.validationErrors == [.startDateAfterDueDate])
    }
}
