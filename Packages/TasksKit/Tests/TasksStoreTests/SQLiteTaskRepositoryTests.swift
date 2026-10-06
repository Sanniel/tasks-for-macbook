import Foundation
import Testing
import TasksCore
@testable import TasksStore

@Suite struct SQLiteTaskRepositoryTests {
    let repo: SQLiteTaskRepository
    // Whole milliseconds, matching the database's timestamp precision.
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        repo = try SQLiteTaskRepository.inMemory()
    }

    private func makeArea(_ name: String = "Private", order: Int = 0) -> Area {
        Area(name: name, colorHex: "#3366FF", sortOrder: order, createdAt: t0)
    }

    @Test func roundTripsAllTaskFields() throws {
        let area = makeArea()
        let task = TaskItem(
            title: "Pay rent", areaID: area.id, priority: .high, notes: "Before noon",
            startDate: LocalDate(isoString: "2026-10-01"), dueDate: LocalDate(isoString: "2026-10-05"),
            recurrence: RecurrenceRule(pattern: .monthly(days: [5]), endDate: LocalDate(isoString: "2027-10-05")!),
            completedAt: t0.addingTimeInterval(60), archivedAt: t0.addingTimeInterval(120),
            archivedWithArea: true, previousOccurrenceID: UUID(), createdAt: t0, updatedAt: t0.addingTimeInterval(180))
        try repo.apply(ChangeSet(areas: [area], tasks: [task]))

        #expect(try repo.fetchArea(id: area.id) == area)
        #expect(try repo.fetchTask(id: task.id) == task)
    }

    @Test func saveUpdatesInPlaceWithoutDroppingSubtasks() throws {
        let area = makeArea()
        var task = TaskItem(title: "Draft", areaID: area.id, createdAt: t0)
        let subtask = Subtask(taskID: task.id, title: "Outline", sortOrder: 0, createdAt: t0)
        try repo.apply(ChangeSet(areas: [area], tasks: [task], subtasks: [subtask]))

        task.title = "Final"
        try repo.save(task)

        #expect(try repo.fetchTask(id: task.id)?.title == "Final")
        #expect(try repo.fetchSubtasks(taskID: task.id) == [subtask])
    }

    @Test func filtersByStatusAndArea() throws {
        let a = makeArea("A", order: 0), b = makeArea("B", order: 1)
        let open = TaskItem(title: "open", areaID: a.id, createdAt: t0)
        let done = TaskItem(title: "done", areaID: a.id, completedAt: t0, createdAt: t0)
        let archived = TaskItem(title: "archived", areaID: a.id, archivedAt: t0, createdAt: t0)
        let otherArea = TaskItem(title: "other", areaID: b.id, createdAt: t0)
        try repo.apply(ChangeSet(areas: [a, b], tasks: [open, done, archived, otherArea]))

        func titles(_ q: TaskQuery) throws -> Set<String> { Set(try repo.fetchTasks(q).map(\.title)) }
        #expect(try titles(TaskQuery(status: .open)) == ["open", "other"])
        #expect(try titles(TaskQuery(status: .open, areaID: a.id)) == ["open"])
        #expect(try titles(TaskQuery(status: .completed)) == ["done"])
        #expect(try titles(TaskQuery(status: .archived)) == ["archived"])
        #expect(try titles(TaskQuery(status: .all)).count == 4)
    }

    @Test func areasSortedAndArchivedHidden() throws {
        var hidden = makeArea("Hidden", order: 0)
        hidden.archivedAt = t0
        try repo.apply(ChangeSet(areas: [makeArea("Second", order: 2), makeArea("First", order: 1), hidden]))

        #expect(try repo.fetchAreas(includeArchived: false).map(\.name) == ["First", "Second"])
        #expect(try repo.fetchAreas(includeArchived: true).map(\.name) == ["Hidden", "First", "Second"])
    }

    @Test func purgingTaskRemovesSubtasksAndLeavesTombstone() throws {
        let area = makeArea()
        let task = TaskItem(title: "T", areaID: area.id, createdAt: t0)
        let sub = Subtask(taskID: task.id, title: "S", sortOrder: 0, createdAt: t0)
        try repo.apply(ChangeSet(areas: [area], tasks: [task], subtasks: [sub]))

        try repo.apply(ChangeSet(purgedTaskIDs: [task.id]), at: t0)

        #expect(try repo.fetchTask(id: task.id) == nil)
        #expect(try repo.fetchSubtasks(taskIDs: nil).isEmpty)
        #expect(try repo.fetchTombstones() == [Tombstone(id: task.id, entityType: .task, deletedAt: t0)])
    }

    @Test func purgingAreaPurgesAllItsTasksWithTombstones() throws {
        let area = makeArea(), keep = makeArea("Keep", order: 1)
        let open = TaskItem(title: "open", areaID: area.id, createdAt: t0)
        let done = TaskItem(title: "done", areaID: area.id, completedAt: t0, createdAt: t0)
        let other = TaskItem(title: "other", areaID: keep.id, createdAt: t0)
        try repo.apply(ChangeSet(areas: [area, keep], tasks: [open, done, other]))

        try repo.apply(ChangeSet(purgedAreaIDs: [area.id]), at: t0)

        #expect(try repo.fetchTasks(TaskQuery(status: .all)).map(\.id) == [other.id])
        let tombstones = try repo.fetchTombstones()
        #expect(Set(tombstones.map(\.id)) == [area.id, open.id, done.id])
        #expect(tombstones.first { $0.id == area.id }?.entityType == .area)
    }

    @Test func purgingMissingRecordLeavesNoTombstone() throws {
        try repo.apply(ChangeSet(purgedTaskIDs: [UUID()]), at: t0)
        #expect(try repo.fetchTombstones().isEmpty)
    }

    @Test func prunesOldTombstones() throws {
        let area = makeArea()
        let old = TaskItem(title: "old", areaID: area.id, createdAt: t0)
        let recent = TaskItem(title: "recent", areaID: area.id, createdAt: t0)
        try repo.apply(ChangeSet(areas: [area], tasks: [old, recent]))
        try repo.apply(ChangeSet(purgedTaskIDs: [old.id]), at: t0)
        try repo.apply(ChangeSet(purgedTaskIDs: [recent.id]), at: t0.addingTimeInterval(86_400))

        try repo.pruneTombstones(before: t0.addingTimeInterval(3600))

        #expect(try repo.fetchTombstones().map(\.id) == [recent.id])
    }

    @Test func changeSetIsAtomic() throws {
        let area = makeArea()
        // Task references a non-existent area: the foreign key fails, so the area is not saved either.
        let orphan = TaskItem(title: "orphan", areaID: UUID(), createdAt: t0)
        #expect(throws: (any Error).self) {
            try repo.apply(ChangeSet(areas: [area], tasks: [orphan]))
        }
        #expect(try repo.fetchAreas(includeArchived: true).isEmpty)
    }

    @Test func persistsAcrossReopenOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "tasks.sqlite")
        let area = makeArea()
        try SQLiteTaskRepository(url: url).save(area)

        // A second connection (as the widget process would open) sees the data.
        #expect(try SQLiteTaskRepository(url: url).fetchAreas(includeArchived: false) == [area])
    }
}
