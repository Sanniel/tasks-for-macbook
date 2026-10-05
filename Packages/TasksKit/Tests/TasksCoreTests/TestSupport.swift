import Foundation
@testable import TasksCore

/// Parses a `YYYY-MM-DD` literal; crashes on typos so tests fail loudly.
func d(_ iso: String) -> LocalDate {
    guard let date = LocalDate(isoString: iso) else { fatalError("Bad test date \(iso)") }
    return date
}

/// Gregorian calendar in UTC, so tests don't depend on the machine's time zone.
let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// Noon UTC on the given day.
func instant(_ iso: String, hour: Int = 12) -> Date {
    d(iso).startOfDay(in: utc).addingTimeInterval(TimeInterval(hour * 3600))
}
