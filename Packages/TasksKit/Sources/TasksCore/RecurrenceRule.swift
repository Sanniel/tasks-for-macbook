/// How a recurring task repeats. Plain data, serialized as JSON:
///
///     {"type":"weekly","weekdays":[1,4],"endDate":"2026-12-31"}
///     {"type":"monthly","days":[1,15,31],"endDate":"2027-06-30"}
///
/// Weekdays use ISO numbering (1 = Monday … 7 = Sunday). Month days are 1…31; a day
/// that doesn't exist in a month falls on that month's last day.
/// A rule always has an end date: there are no open-ended repeats.
public struct RecurrenceRule: Hashable, Sendable {
    public enum Pattern: Hashable, Sendable {
        case weekly(weekdays: Set<Weekday>)
        case monthly(days: Set<Int>)
    }

    public var pattern: Pattern
    /// Inclusive: an occurrence may fall on this date, never after it.
    public var endDate: LocalDate

    public init(pattern: Pattern, endDate: LocalDate) {
        self.pattern = pattern
        self.endDate = endDate
    }
}

/// ISO 8601 weekday numbering.
public enum Weekday: Int, CaseIterable, Codable, Sendable, Comparable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension RecurrenceRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, weekdays, days, endDate
    }

    private enum PatternType: String, Codable {
        case weekly, monthly
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        endDate = try c.decode(LocalDate.self, forKey: .endDate)
        switch try c.decode(PatternType.self, forKey: .type) {
        case .weekly:
            let weekdays = try c.decode([Weekday].self, forKey: .weekdays)
            pattern = .weekly(weekdays: Set(weekdays))
        case .monthly:
            let days = try c.decode([Int].self, forKey: .days)
            guard days.allSatisfy({ (1...31).contains($0) }) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .days, in: c, debugDescription: "Month days must be 1...31")
            }
            pattern = .monthly(days: Set(days))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch pattern {
        case .weekly(let weekdays):
            try c.encode(PatternType.weekly, forKey: .type)
            try c.encode(weekdays.sorted(), forKey: .weekdays)
        case .monthly(let days):
            try c.encode(PatternType.monthly, forKey: .type)
            try c.encode(days.sorted(), forKey: .days)
        }
        try c.encode(endDate, forKey: .endDate)
    }
}
