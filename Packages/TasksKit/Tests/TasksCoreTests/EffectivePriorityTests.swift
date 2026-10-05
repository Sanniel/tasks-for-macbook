import Foundation
import Testing
@testable import TasksCore

@Suite struct EffectivePriorityTests {
    let today = d("2026-10-05")

    /// The due-date floor table from the spec, at each boundary.
    static let floors: [(days: Int, floor: Priority?)] = [
        (8, nil), (7, .raised), (5, .raised), (4, .high), (2, .high), (1, .urgent), (0, .urgent), (-3, .urgent),
    ]

    @Test(arguments: [8, 7, 5, 4, 2, 1, 0, -3])
    func floorAtBoundary(days: Int) {
        let expected = Self.floors.first { $0.days == days }!.floor
        #expect(EffectivePriority.dueDateFloor(daysUntilDue: days) == expected)
    }

    @Test(arguments: [8, 7, 5, 4, 2, 1, 0, -3], Priority.allCases)
    func effectiveIsMaxOfStoredAndFloor(days: Int, stored: Priority) {
        let floor = Self.floors.first { $0.days == days }!.floor
        let result = EffectivePriority(stored: stored, dueDate: today.adding(days: days), today: today)
        let expected = max(stored, floor ?? .low)
        #expect(result.value == expected)
        #expect(result.isRaisedByDueDate == (expected > stored))
    }

    @Test(arguments: Priority.allCases)
    func noDueDateMeansStoredPriority(stored: Priority) {
        let result = EffectivePriority(stored: stored, dueDate: nil, today: today)
        #expect(result.value == stored)
        #expect(!result.isRaisedByDueDate)
    }

    @Test func specExamples() {
        // Low task due in 6 days → 1.
        #expect(EffectivePriority(stored: .low, dueDate: today.adding(days: 6), today: today).value == .raised)
        // High task stays 2 until the day before it's due, then 3.
        let due = d("2026-10-20")
        #expect(EffectivePriority(stored: .high, dueDate: due, today: d("2026-10-18")).value == .high)
        #expect(EffectivePriority(stored: .high, dueDate: due, today: d("2026-10-19")).value == .urgent)
        // Urgent never drops.
        #expect(EffectivePriority(stored: .urgent, dueDate: today.adding(days: 30), today: today).value == .urgent)
    }

    @Test func recomputesWhenTheDayChanges() {
        // Same task, evaluated on consecutive days around midnight.
        let task = TaskItem(title: "Report", areaID: UUID(), dueDate: d("2026-10-10"))
        #expect(EffectivePriority(task, today: d("2026-10-02")).value == .normal)  // 8 days
        #expect(EffectivePriority(task, today: d("2026-10-03")).value == .raised)  // 7 days
        #expect(EffectivePriority(task, today: d("2026-10-05")).value == .raised)  // 5 days
        #expect(EffectivePriority(task, today: d("2026-10-06")).value == .high)    // 4 days
        #expect(EffectivePriority(task, today: d("2026-10-09")).value == .urgent)  // 1 day
    }
}
