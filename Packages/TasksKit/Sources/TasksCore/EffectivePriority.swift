/// The priority a task is shown and sorted with. Computed, never stored.
///
///     effective = max(storedPriority, dueDateFloor)
///
/// where `daysUntilDue` = calendar days from today to the due date (local time zone):
///
/// | daysUntilDue          | floor        |
/// |-----------------------|--------------|
/// | no due date           | none         |
/// | <= 1 (tomorrow, today, overdue) | 3 (Urgent) |
/// | <= 4                  | 2 (High)     |
/// | <= 7                  | 1 (Raised)   |
/// | > 7                   | none         |
///
/// Because it depends on "today", it must be recomputed when the day changes.
public struct EffectivePriority: Hashable, Sendable {
    public let value: Priority
    /// True when the due date lifted the priority above the stored one
    /// (shown subtly in the UI).
    public let isRaisedByDueDate: Bool

    public init(stored: Priority, dueDate: LocalDate?, today: LocalDate) {
        let floor = dueDate.flatMap { Self.dueDateFloor(daysUntilDue: today.days(until: $0)) }
        if let floor, floor > stored {
            value = floor
            isRaisedByDueDate = true
        } else {
            value = stored
            isRaisedByDueDate = false
        }
    }

    public init(_ task: TaskItem, today: LocalDate) {
        self.init(stored: task.priority, dueDate: task.dueDate, today: today)
    }

    /// The minimum priority implied by a due date `daysUntilDue` days away, if any.
    public static func dueDateFloor(daysUntilDue: Int) -> Priority? {
        switch daysUntilDue {
        case ...1: .urgent
        case ...4: .high
        case ...7: .raised
        default: nil
        }
    }
}
