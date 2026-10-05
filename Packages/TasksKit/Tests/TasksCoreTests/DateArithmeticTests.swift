import Foundation
import Testing
@testable import TasksCore

@Suite struct DateArithmeticTests {
    @Test func epochIsDayZero() {
        #expect(d("1970-01-01").dayNumber == 0)
        #expect(d("1969-12-31").dayNumber == -1)
        #expect(LocalDate(dayNumber: 0) == d("1970-01-01"))
    }

    @Test func matchesFoundationCalendarOverManyYears() {
        // Every 13th day from 1900 to 2200, compared with Foundation's Gregorian calendar.
        let start = d("1900-01-01").dayNumber, end = d("2200-12-31").dayNumber
        for n in stride(from: start, through: end, by: 13) {
            let date = LocalDate(dayNumber: n)
            #expect(date.dayNumber == n)
            let foundation = LocalDate(Date(timeIntervalSince1970: TimeInterval(n) * 86_400), calendar: utc)
            #expect(date == foundation)
        }
    }

    @Test func addingDaysCrossesMonthYearAndLeapDay() {
        #expect(d("2026-12-31").adding(days: 1) == d("2027-01-01"))
        #expect(d("2028-02-28").adding(days: 1) == d("2028-02-29"))
        #expect(d("2027-02-28").adding(days: 1) == d("2027-03-01"))
        #expect(d("2026-03-01").adding(days: -1) == d("2026-02-28"))
        #expect(d("2026-10-05").days(until: d("2026-10-12")) == 7)
        #expect(d("2026-10-05").days(until: d("2026-10-02")) == -3)
    }

    @Test func weekdays() {
        #expect(d("1970-01-01").weekday == .thursday)
        #expect(d("2026-10-05").weekday == .monday)
        #expect(d("2026-10-11").weekday == .sunday)
        #expect(d("2000-02-29").weekday == .tuesday)
    }

    @Test func todayUsesCalendarTimeZone() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let lateEveningUTC = instant("2026-10-05", hour: 20)
        #expect(LocalDate.today(calendar: utc, now: lateEveningUTC) == d("2026-10-05"))
        #expect(LocalDate.today(calendar: tokyo, now: lateEveningUTC) == d("2026-10-06"))
    }
}
