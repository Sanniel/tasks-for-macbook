import Foundation

/// Sort order used by every task list and the widget.
///
/// Started tasks (no start date, or start date on/before today) come first:
///   0. Overdue tasks (due before today) above everything else, oldest due date first.
///   1. Effective priority, descending.
///   2. Due date, ascending; tasks without a due date after dated ones.
///   3. Area, by the user-defined area order (`Area.sortOrder`).
///   4. Title, alphabetical (case-insensitive, locale-aware).
///   5. Tiebreak for a stable order: createdAt, then id.
///
/// Not-started tasks (start date after today) always come last, ordered by start date
/// ascending, then by the same rules 0–5.
public enum TaskOrdering {
    public static func sorted(
        _ tasks: [TaskItem], areas: [Area], today: LocalDate, locale: Locale = .current
    ) -> [TaskItem] {
        let areaRank = Dictionary(
            areas.map { ($0.id, ($0.sortOrder, $0.name)) }, uniquingKeysWith: { a, _ in a })
        return tasks
            .map { SortKey(task: $0, today: today) }
            .sorted { lhs, rhs in
                areSorted(lhs, rhs, areaRank: areaRank, locale: locale)
            }
            .map(\.task)
    }

    /// Completed tasks for the Done view: newest completion first.
    public static func sortedByCompletion(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted {
            ($0.completedAt ?? .distantPast, $0.id.uuidString) > ($1.completedAt ?? .distantPast, $1.id.uuidString)
        }
    }

    private struct SortKey {
        let task: TaskItem
        let notStartedSince: LocalDate?  // start date, if not started yet
        let isOverdue: Bool
        let effective: Int

        init(task: TaskItem, today: LocalDate) {
            self.task = task
            notStartedSince = task.isStarted(today: today) ? nil : task.startDate
            isOverdue = task.isOverdue(today: today)
            effective = EffectivePriority(task, today: today).value.rawValue
        }
    }

    private static func areSorted(
        _ a: SortKey, _ b: SortKey, areaRank: [UUID: (Int, String)], locale: Locale
    ) -> Bool {
        // Not-started tasks last, by start date.
        switch (a.notStartedSince, b.notStartedSince) {
        case (nil, .some): return true
        case (.some, nil): return false
        case let (.some(x), .some(y)) where x != y: return x < y
        default: break
        }
        // 0. Overdue first, oldest due date first.
        if a.isOverdue != b.isOverdue { return a.isOverdue }
        if a.isOverdue, let x = a.task.dueDate, let y = b.task.dueDate, x != y { return x < y }
        // 1. Effective priority, descending.
        if a.effective != b.effective { return a.effective > b.effective }
        // 2. Due date ascending, undated last.
        switch (a.task.dueDate, b.task.dueDate) {
        case (.some, nil): return true
        case (nil, .some): return false
        case let (.some(x), .some(y)) where x != y: return x < y
        default: break
        }
        // 3. Area order. Unknown areas last.
        let rankA = areaRank[a.task.areaID], rankB = areaRank[b.task.areaID]
        switch (rankA, rankB) {
        case (.some, nil): return true
        case (nil, .some): return false
        case let (.some(x), .some(y)) where x.0 != y.0: return x.0 < y.0
        case let (.some(x), .some(y)) where x.1 != y.1: return x.1 < y.1
        default: break
        }
        // 4. Title.
        let titleOrder = a.task.title.compare(
            b.task.title, options: [.caseInsensitive], range: nil, locale: locale)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        // 5. Stable tiebreak.
        if a.task.createdAt != b.task.createdAt { return a.task.createdAt < b.task.createdAt }
        return a.task.id.uuidString < b.task.id.uuidString
    }
}
