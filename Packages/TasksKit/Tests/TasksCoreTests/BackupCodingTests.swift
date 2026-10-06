import Foundation
import Testing
@testable import TasksCore

@Suite struct BackupCodingTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000.123)

    private func sampleDocument() -> BackupDocument {
        let area = Area(name: "Private", colorHex: "#0090FF", sortOrder: 0, createdAt: t0)
        let task = TaskItem(
            title: "Gym", areaID: area.id, priority: .high, notes: "Leg day",
            startDate: d("2026-10-04"), dueDate: d("2026-10-05"),
            recurrence: RecurrenceRule(pattern: .weekly(weekdays: [.monday]), endDate: d("2026-12-31")),
            previousOccurrenceID: UUID(), createdAt: t0, updatedAt: t0.addingTimeInterval(5))
        let subtask = Subtask(taskID: task.id, title: "Shoes", isDone: true, sortOrder: 0, createdAt: t0)
        return BackupDocument(
            exportedAt: t0, areas: [area], tasks: [task], subtasks: [subtask],
            tombstones: [Tombstone(id: UUID(), entityType: .task, deletedAt: t0)])
    }

    @Test func roundTrips() throws {
        let document = sampleDocument()
        #expect(try Backup.decode(Backup.encode(document)) == document)
    }

    @Test func usesPortableValueFormats() throws {
        let json = String(decoding: try Backup.encode(sampleDocument()), as: UTF8.self)
        #expect(json.contains(#""format" : "fi.sannier.tasks.backup""#))
        #expect(json.contains(#""version" : 1"#))
        #expect(json.contains(#""dueDate" : "2026-10-05""#))
        #expect(json.contains(#""exportedAt" : "2026-09-21T14:13:20.123Z""#))
        #expect(json.contains(#""type" : "weekly""#))
        #expect(json.contains(#""priority" : 2"#))
        #expect(!json.contains("completedAt"))  // nil values are omitted
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: BackupError.notJSON("not a JSON object")) { try Backup.decode(Data("hello".utf8)) }
        #expect(throws: BackupError.wrongFormat) { try Backup.decode(Data(#"{"format":"other","version":1}"#.utf8)) }
        #expect(throws: BackupError.unsupportedVersion(2)) {
            try Backup.decode(Data(#"{"format":"fi.sannier.tasks.backup","version":2}"#.utf8))
        }
    }

    @Test func reportsWhereABrokenFileFails() throws {
        var json = String(decoding: try Backup.encode(sampleDocument()), as: UTF8.self)
        json = json.replacingOccurrences(of: #""dueDate" : "2026-10-05""#, with: #""dueDate" : "5.10.2026""#)
        do {
            _ = try Backup.decode(Data(json.utf8))
            Issue.record("Expected a decoding error")
        } catch let error as BackupError {
            guard case .notJSON(let detail) = error else { Issue.record("Wrong error \(error)"); return }
            #expect(detail.contains("tasks"))
            #expect(detail.contains("dueDate"))
        }
    }

    @Test func millisecondComparison() {
        #expect(!Backup.isNewer(t0.addingTimeInterval(0.0000001), than: t0))
        #expect(Backup.isNewer(t0.addingTimeInterval(0.001), than: t0))
    }
}
