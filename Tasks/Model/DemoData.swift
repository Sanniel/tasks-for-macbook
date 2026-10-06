#if DEBUG
import Foundation
import TasksCore
import TasksStore

/// Debug-only sample data, used when the app is launched with `-demo`.
/// It lives in an in-memory database, so the real one is never touched.
enum DemoData {
    static func makeRepository() throws -> SQLiteTaskRepository {
        let repo = try SQLiteTaskRepository.inMemory()
        let today = LocalDate.today()
        let now = Date()
        func day(_ offset: Int) -> LocalDate { today.adding(days: offset) }

        let priv = Area(name: "Private", colorName: "Sage", sortOrder: 0)
        let learning = Area(name: "Learning", colorName: "Slate", sortOrder: 1)
        let client = Area(name: "Client X", colorName: "Terracotta", sortOrder: 2)
        var oldArea = Area(name: "Old project", colorName: "Clay", sortOrder: 3)
        oldArea.archivedAt = now.addingTimeInterval(-5 * 86_400)

        let report = TaskItem(title: "Send monthly report", areaID: client.id, priority: .high, dueDate: day(-2))
        let invoice = TaskItem(title: "Invoice September", areaID: client.id, dueDate: day(0))
        let course = TaskItem(
            title: "Finish SwiftUI course module", areaID: learning.id, priority: .low, notes: "Chapters 4–6",
            dueDate: day(6))
        let dentist = TaskItem(title: "Book dentist appointment", areaID: priv.id, priority: .raised)
        let gym = TaskItem(
            title: "Gym", areaID: priv.id, dueDate: day(1),
            recurrence: RecurrenceRule(pattern: .weekly(weekdays: [.monday, .thursday]), endDate: day(90)))
        let rent = TaskItem(
            title: "Pay rent", areaID: priv.id, priority: .urgent, dueDate: day(10),
            recurrence: RecurrenceRule(pattern: .monthly(days: [31]), endDate: day(15)))
        let trip = TaskItem(title: "Plan summer trip", areaID: priv.id, startDate: day(3), dueDate: day(20))
        let book = TaskItem(title: "read: Designing Data-Intensive Apps", areaID: learning.id)
        let workshop = TaskItem(title: "Prepare workshop", areaID: client.id, priority: .high, dueDate: day(4))
        var done = TaskItem(title: "Renew passport", areaID: priv.id)
        done.completedAt = now.addingTimeInterval(-3 * 86_400)
        var archived = TaskItem(title: "Old idea", areaID: learning.id)
        archived.archivedAt = now.addingTimeInterval(-12 * 86_400)
        var oldTask = TaskItem(title: "Wrap up old project", areaID: oldArea.id)
        oldTask.archivedAt = oldArea.archivedAt
        oldTask.archivedWithArea = true

        let subtasks = [
            Subtask(taskID: workshop.id, title: "Agenda", isDone: true, sortOrder: 0),
            Subtask(taskID: workshop.id, title: "Slides", isDone: true, sortOrder: 1),
            Subtask(taskID: workshop.id, title: "Exercises", sortOrder: 2),
            Subtask(taskID: workshop.id, title: "Book room", sortOrder: 3),
            Subtask(taskID: workshop.id, title: "Send invites", sortOrder: 4),
        ]

        try repo.apply(ChangeSet(
            areas: [priv, learning, client, oldArea],
            tasks: [report, invoice, course, dentist, gym, rent, trip, book, workshop, done, archived, oldTask],
            subtasks: subtasks))
        return repo
    }
}
#endif
