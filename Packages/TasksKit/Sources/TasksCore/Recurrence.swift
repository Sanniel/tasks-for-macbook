// Date generation for recurring tasks.
//
// A recurring task has a due date; each completion creates the next occurrence,
// whose due date is the next pattern date strictly after the current due date
// (not after the completion day), unless that date is after the rule's end date.

extension RecurrenceRule {
    /// A rule is usable only if it selects at least one weekday / month day.
    public var isValid: Bool {
        switch pattern {
        case .weekly(let weekdays): !weekdays.isEmpty
        case .monthly(let days): !days.isEmpty && days.allSatisfy { (1...31).contains($0) }
        }
    }

    /// The first pattern date strictly after `date` and on or before `endDate`,
    /// or nil if the series has ended.
    ///
    /// Monthly: a selected day that doesn't exist in a month (e.g. the 31st in April)
    /// falls on that month's last day. If several selected days collapse onto the
    /// same last day (29, 30, 31 in February) it is a single occurrence.
    public func nextOccurrence(after date: LocalDate) -> LocalDate? {
        guard isValid else { return nil }
        let next: LocalDate
        switch pattern {
        case .weekly(let weekdays):
            // Some weekday within the next 7 days always matches.
            next = (1...7).lazy.map { date.adding(days: $0) }.first { weekdays.contains($0.weekday) }!
        case .monthly(let days):
            var year = date.year, month = date.month
            while true {
                let lastDay = LocalDate.daysInMonth(year: year, month: month)
                let candidates = Set(days.map { min($0, lastDay) }).sorted()
                    .map { LocalDate(year: year, month: month, day: $0)! }
                if let match = candidates.first(where: { $0 > date }) {
                    next = match
                    break
                }
                month += 1
                if month > 12 { month = 1; year += 1 }
            }
        }
        return next <= endDate ? next : nil
    }

    /// All occurrences strictly after `date`, through `endDate`. Mainly for previews and tests.
    public func occurrences(after date: LocalDate) -> [LocalDate] {
        var result: [LocalDate] = []
        var current = date
        while let next = nextOccurrence(after: current) {
            result.append(next)
            current = next
        }
        return result
    }
}
