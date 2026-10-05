// Date-dependent task states. "today" is always passed in so callers control
// when the day rolls over (app open over midnight, widget refresh at midnight).

extension TaskItem {
    /// Neither completed nor archived.
    public var isOpen: Bool { completedAt == nil && archivedAt == nil }

    /// A task with a start date in the future is not started yet: it is shown greyed
    /// out at the bottom of lists and hidden from the widget. On the start date it
    /// becomes started.
    public func isStarted(today: LocalDate) -> Bool {
        guard let startDate else { return true }
        return startDate <= today
    }

    /// Due date is before today. Overdue tasks sort above everything else and are shown red.
    public func isOverdue(today: LocalDate) -> Bool {
        guard let dueDate else { return false }
        return dueDate < today
    }

    public var isRecurring: Bool { recurrence != nil }

    /// A recurring task whose pattern has no occurrence after this one's due date
    /// (on or before the rule's end date): completing it will not create a new one.
    public var isLastOccurrence: Bool {
        guard let recurrence, let dueDate else { return false }
        return recurrence.nextOccurrence(after: dueDate) == nil
    }
}
