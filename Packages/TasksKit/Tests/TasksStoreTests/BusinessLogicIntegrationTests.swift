import Foundation
import Testing
import TasksCore
@testable import TasksStore

/// TasksCore logic run against the real SQLite repository.
@Suite struct BusinessLogicIntegrationTests {
    let repo: SQLiteTaskRepository
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        repo = try SQLiteTaskRepository.inMemory()
    }

    private func days(_ n: Int) -> Date { t0.addingTimeInterval(TimeInterval(n) * 86_400) }

    @Test func purgeRunRemovesExpiredRecordsAndPrunesTombstones() throws {
        var oldArea = Area(name: "Old", colorHex: "#000000", sortOrder: 0, createdAt: t0)
        let keepArea = Area(name: "Keep", colorHex: "#000000", sortOrder: 1, createdAt: t0)
        let inOldArea = TaskItem(title: "in old area", areaID: oldArea.id, completedAt: days(10), createdAt: t0)
        let oldDone = TaskItem(title: "old done", areaID: keepArea.id, completedAt: t0, createdAt: t0)
        let recentDone = TaskItem(title: "recent done", areaID: keepArea.id, completedAt: days(20), createdAt: t0)
        let open = TaskItem(title: "open", areaID: keepArea.id, createdAt: t0)
        oldArea.archivedAt = t0
        try repo.apply(ChangeSet(areas: [oldArea, keepArea], tasks: [inOldArea, oldDone, recentDone, open]))

        try Purge.run(on: repo, now: days(31))

        #expect(try repo.fetchAreas(includeArchived: true).map(\.name) == ["Keep"])
        #expect(Set(try repo.fetchTasks(TaskQuery(status: .all)).map(\.title)) == ["recent done", "open"])
        #expect(Set(try repo.fetchTombstones().map(\.id)) == [oldArea.id, inOldArea.id, oldDone.id])

        // 90 days later the tombstones are pruned (recent done is purged on the way).
        try Purge.run(on: repo, now: days(31 + 91))
        #expect(try repo.fetchTombstones().map(\.id) == [recentDone.id])
    }

    @Test func setSubtaskTicksItemAndTouchesTask() throws {
        let area = Area(name: "Home", colorHex: "#000000", sortOrder: 0, createdAt: t0)
        let task = TaskItem(title: "Clean", areaID: area.id, createdAt: t0)
        let sub = Subtask(taskID: task.id, title: "Kitchen", sortOrder: 0, createdAt: t0)
        try repo.apply(ChangeSet(areas: [area], tasks: [task], subtasks: [sub]))

        try repo.setSubtask(id: sub.id, done: true, now: days(1))

        #expect(try repo.fetchSubtasks(taskID: task.id).first?.isDone == true)
        #expect(try repo.fetchTask(id: task.id)?.updatedAt == days(1))
    }

    @Test func completeTaskCreatesNextOccurrenceWithSubtasks() throws {
        let area = Area(name: "Home", colorHex: "#000000", sortOrder: 0, createdAt: t0)
        let task = TaskItem(
            title: "Bins", areaID: area.id, dueDate: LocalDate(isoString: "2026-10-05"),
            recurrence: RecurrenceRule(pattern: .weekly(weekdays: [.monday]), endDate: LocalDate(isoString: "2026-12-31")!),
            createdAt: t0)
        let sub = Subtask(taskID: task.id, title: "Recycling", isDone: true, sortOrder: 0, createdAt: t0)
        try repo.apply(ChangeSet(areas: [area], tasks: [task], subtasks: [sub]))

        try repo.completeTask(id: task.id, now: days(1))
        try repo.completeTask(id: task.id, now: days(2))  // second tap is a no-op

        let open = try repo.fetchTasks(TaskQuery(status: .open))
        #expect(open.count == 1)
        #expect(open[0].dueDate == LocalDate(isoString: "2026-10-12"))
        let nextSubs = try repo.fetchSubtasks(taskID: open[0].id)
        #expect(nextSubs.map(\.title) == ["Recycling"] && !nextSubs[0].isDone)
        #expect(try repo.fetchTask(id: task.id)?.completedAt == days(1))
    }
}
