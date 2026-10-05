import Foundation
import Testing
@testable import TasksCore

@Suite struct TaskOrderingTests {
    let today = d("2026-10-05")
    let first = Area(name: "First", colorHex: "#000000", sortOrder: 0)
    let second = Area(name: "Second", colorHex: "#000000", sortOrder: 1)

    private func task(
        _ title: String, area: Area? = nil, priority: Priority = .normal,
        start: String? = nil, due: String? = nil
    ) -> TaskItem {
        TaskItem(
            title: title, areaID: (area ?? first).id, priority: priority,
            startDate: start.map(d), dueDate: due.map(d))
    }

    private func order(_ tasks: [TaskItem]) -> [String] {
        TaskOrdering.sorted(
            tasks, areas: [second, first], today: today, locale: Locale(identifier: "en_US")
        ).map(\.title)
    }

    @Test func overdueFirstOldestFirstRegardlessOfPriority() {
        let tasks = [
            task("urgent no date", priority: .urgent),
            task("due today", due: "2026-10-05"),
            task("overdue 1 day", priority: .low, due: "2026-10-04"),
            task("overdue 5 days", priority: .low, due: "2026-09-30"),
        ]
        #expect(order(tasks) == ["overdue 5 days", "overdue 1 day", "due today", "urgent no date"])
    }

    @Test func effectivePriorityDescending() {
        let tasks = [
            task("low", priority: .low),
            task("raised by due date in 6 days", priority: .low, due: "2026-10-11"),
            task("high", priority: .high),
            task("normal"),
        ]
        #expect(order(tasks) == ["high", "raised by due date in 6 days", "normal", "low"])
    }

    @Test func dueDateAscendingUndatedLast() {
        let tasks = [
            task("no date", priority: .high),
            task("in 20 days", priority: .high, due: "2026-10-25"),
            task("in 10 days", priority: .high, due: "2026-10-15"),
        ]
        #expect(order(tasks) == ["in 10 days", "in 20 days", "no date"])
    }

    @Test func areaOrderThenTitle() {
        let tasks = [
            task("b", area: second),
            task("a", area: second),
            task("Z", area: first),
            task("c", area: first),
        ]
        #expect(order(tasks) == ["c", "Z", "a", "b"])
    }

    @Test func titleIsCaseInsensitive() {
        #expect(order([task("banana"), task("Apple"), task("cherry")]) == ["Apple", "banana", "cherry"])
    }

    @Test func notStartedLastByStartDateThenNormalRules() {
        let tasks = [
            task("starts in 3 days low", priority: .low, start: "2026-10-08"),
            task("starts in 3 days urgent", priority: .urgent, start: "2026-10-08"),
            task("starts tomorrow", start: "2026-10-06"),
            task("open low", priority: .low),
            task("started today", start: "2026-10-05"),
        ]
        #expect(order(tasks) == [
            "started today", "open low",
            "starts tomorrow", "starts in 3 days urgent", "starts in 3 days low",
        ])
    }

    @Test func doneViewNewestCompletionFirst() {
        var older = task("older"), newer = task("newer")
        older.completedAt = instant("2026-10-01")
        newer.completedAt = instant("2026-10-03")
        #expect(TaskOrdering.sortedByCompletion([older, newer]).map(\.title) == ["newer", "older"])
    }
}
