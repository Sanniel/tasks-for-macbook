import Foundation
import Testing
import TasksCore
@testable import TasksStore

/// Export and merge-import against the real SQLite repository.
@Suite struct BackupMergeTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func populated() throws -> SQLiteTaskRepository {
        let repo = try SQLiteTaskRepository.inMemory()
        let area = Area(name: "Private", colorHex: "#0090FF", sortOrder: 0, createdAt: t0)
        let open = TaskItem(
            title: "Gym", areaID: area.id, dueDate: LocalDate(isoString: "2026-10-05"),
            recurrence: RecurrenceRule(pattern: .monthly(days: [5, 31]), endDate: LocalDate(isoString: "2027-01-01")!),
            createdAt: t0)
        let done = TaskItem(title: "Done", areaID: area.id, completedAt: t0, createdAt: t0)
        let purged = TaskItem(title: "Purged", areaID: area.id, createdAt: t0)
        try repo.apply(ChangeSet(
            areas: [area], tasks: [open, done, purged],
            subtasks: [Subtask(taskID: open.id, title: "Shoes", sortOrder: 0, createdAt: t0)]))
        try repo.apply(ChangeSet(purgedTaskIDs: [purged.id]), at: t0)
        return repo
    }

    private func roundTrip(_ document: BackupDocument) throws -> BackupDocument {
        try Backup.decode(Backup.encode(document))
    }

    @Test func importIntoEmptyAppRecreatesEverything() throws {
        let source = try populated()
        let backup = try roundTrip(Backup.export(from: source, now: t0))

        let target = try SQLiteTaskRepository.inMemory()
        let plan = try Backup.mergePlan(backup, into: target)
        #expect(plan.summary == Backup.MergeSummary(added: 4, updated: 0, unchanged: 0))
        try target.apply(plan.changes)

        let restored = try Backup.export(from: target, now: t0)
        #expect(restored == (try Backup.export(from: source, now: t0)))
        #expect(restored.tombstones.count == 1)
    }

    @Test func importingTheSameBackupTwiceChangesNothing() throws {
        let repo = try populated()
        let backup = try roundTrip(Backup.export(from: repo, now: t0))
        let plan = try Backup.mergePlan(backup, into: repo)
        #expect(plan.changes.isEmpty)
        #expect(plan.summary == Backup.MergeSummary(added: 0, updated: 0, unchanged: 4))
    }

    @Test func newerVersionWinsAndNothingIsDeleted() throws {
        let repo = try populated()
        var backup = try roundTrip(Backup.export(from: repo, now: t0))
        let gymIndex = backup.tasks.firstIndex { $0.title == "Gym" }!
        let doneIndex = backup.tasks.firstIndex { $0.title == "Done" }!

        // Backup has a newer Gym; the app has a newer Done; the backup lacks the checklist item.
        backup.tasks[gymIndex].title = "Gym (from backup)"
        backup.tasks[gymIndex].updatedAt = t0.addingTimeInterval(60)
        var localDone = try repo.fetchTask(id: backup.tasks[doneIndex].id)!
        localDone.title = "Done (local edit)"
        localDone.updatedAt = t0.addingTimeInterval(120)
        try repo.save(localDone)
        backup.tasks[doneIndex].title = "Done (old)"
        backup.subtasks = []

        let plan = try Backup.mergePlan(backup, into: repo)
        try repo.apply(plan.changes)

        let titles = Set(try repo.fetchTasks(TaskQuery(status: .all)).map(\.title))
        #expect(titles == ["Gym (from backup)", "Done (local edit)"])
        #expect(try repo.fetchSubtasks(taskIDs: nil).count == 1)  // kept
        #expect(plan.summary == Backup.MergeSummary(added: 0, updated: 1, unchanged: 2))
    }

    @Test func rejectsReferencesToMissingRecords() throws {
        let repo = try SQLiteTaskRepository.inMemory()
        var backup = try roundTrip(Backup.export(from: try populated(), now: t0))
        backup.areas = []
        #expect(throws: BackupError.missingArea(taskTitle: backup.tasks[0].title)) {
            try Backup.mergePlan(backup, into: repo)
        }
    }
}
