import Foundation

/// A calendar date with no time and no time zone, e.g. a start or due date.
///
/// Serialized everywhere (database, JSON) as an ISO 8601 date string `YYYY-MM-DD`,
/// so the same task shows the same date on every device regardless of time zone.
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Returns nil if the components don't form a valid Gregorian date.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...LocalDate.daysInMonth(year: year, month: month)).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses a strict `YYYY-MM-DD` string.
    public init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The local calendar date that `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year!
        self.month = c.month!
        self.day = c.day!
    }

    /// `YYYY-MM-DD`
    public var isoString: String {
        func pad(_ n: Int, _ width: Int) -> String {
            let s = String(n)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    public var description: String { isoString }

    /// Start of this day in `calendar`'s time zone.
    public func startOfDay(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

extension LocalDate: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let date = LocalDate(isoString: string) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected a YYYY-MM-DD date, got \"\(string)\"")
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}
