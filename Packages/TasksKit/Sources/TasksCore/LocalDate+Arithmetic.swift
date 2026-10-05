import Foundation

// Calendar arithmetic on date-only values, done with plain integer maths
// (proleptic Gregorian calendar) so results never depend on time zones or DST
// and the algorithm ports directly to other languages.

extension LocalDate {
    /// Days since 1970-01-01 (which is day 0). Negative before that.
    ///
    /// Algorithm: Howard Hinnant, "days_from_civil"
    /// (http://howardhinnant.github.io/date_algorithms.html).
    public var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let monthFromMarch = (month + 9) % 12
        let dayOfYear = (153 * monthFromMarch + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// Inverse of `dayNumber` ("civil_from_days").
    public init(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthFromMarch = (5 * dayOfYear + 2) / 153
        let d = dayOfYear - (153 * monthFromMarch + 2) / 5 + 1
        let m = monthFromMarch < 10 ? monthFromMarch + 3 : monthFromMarch - 9
        let y = yearOfEra + era * 400 + (m <= 2 ? 1 : 0)
        self.init(year: y, month: m, day: d)!
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(dayNumber: dayNumber + days)
    }

    /// Calendar days from `self` to `other` (positive if `other` is later).
    public func days(until other: LocalDate) -> Int {
        other.dayNumber - dayNumber
    }

    /// ISO weekday. 1970-01-01 (day 0) was a Thursday.
    public var weekday: Weekday {
        let mondayBased = ((dayNumber % 7) + 7 + 3) % 7  // 0 = Monday
        return Weekday(rawValue: mondayBased + 1)!
    }

    /// Today's date in the given calendar's time zone.
    public static func today(calendar: Calendar = .current, now: Date = Date()) -> LocalDate {
        LocalDate(now, calendar: calendar)
    }
}
