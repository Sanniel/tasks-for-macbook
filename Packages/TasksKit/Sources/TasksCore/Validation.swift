import Foundation

/// Rules a task must satisfy before it is saved.
public enum TaskValidationError: Error, Hashable, Sendable {
    case emptyTitle
    /// Recurring tasks need a due date: each occurrence's due date comes from the pattern.
    case recurrenceWithoutDueDate
    /// A weekly rule needs at least one weekday; a monthly rule at least one day (1–31).
    case recurrenceWithoutDays
    case startDateAfterDueDate
}

extension TaskItem {
    public var validationErrors: [TaskValidationError] {
        var errors: [TaskValidationError] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyTitle)
        }
        if let recurrence {
            if dueDate == nil { errors.append(.recurrenceWithoutDueDate) }
            if !recurrence.isValid { errors.append(.recurrenceWithoutDays) }
        }
        if let startDate, let dueDate, startDate > dueDate {
            errors.append(.startDateAfterDueDate)
        }
        return errors
    }
}
