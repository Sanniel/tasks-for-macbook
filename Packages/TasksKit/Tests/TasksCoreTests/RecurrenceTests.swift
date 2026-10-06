import Foundation
import Testing
@testable import TasksCore

@Suite struct RecurrenceTests {
    private func weekly(_ days: Set<Weekday>, until end: String) -> RecurrenceRule {
        RecurrenceRule(pattern: .weekly(weekdays: days), endDate: d(end))
    }

    private func monthly(_ days: Set<Int>, until end: String) -> RecurrenceRule {
        RecurrenceRule(pattern: .monthly(days: days), endDate: d(end))
    }

    @Test func weeklySeveralWeekdays() {
        // 2026-10-05 is a Monday.
        let rule = weekly([.monday, .thursday], until: "2026-10-19")
        #expect(rule.occurrences(after: d("2026-10-05")) == [
            d("2026-10-08"), d("2026-10-12"), d("2026-10-15"), d("2026-10-19"),
        ])
    }

    @Test func weeklySingleDayIsAWeekLater() {
        let rule = weekly([.wednesday], until: "2027-01-01")
        #expect(rule.nextOccurrence(after: d("2026-10-07")) == d("2026-10-14"))
    }

    @Test func weeklyCrossingYearEnd() {
        let rule = weekly([.tuesday, .saturday], until: "2027-01-10")
        #expect(rule.occurrences(after: d("2026-12-26")) == [
            d("2026-12-29"), d("2027-01-02"), d("2027-01-05"), d("2027-01-09"),
        ])
    }

    @Test func monthlyThirtyFirstFallsOnLastDay() {
        let rule = monthly([31], until: "2026-06-30")
        #expect(rule.occurrences(after: d("2026-01-31")) == [
            d("2026-02-28"), d("2026-03-31"), d("2026-04-30"), d("2026-05-31"), d("2026-06-30"),
        ])
    }

    @Test func monthly29to31CollapseInFebruary() {
        let rule = monthly([29, 30, 31], until: "2026-03-31")
        #expect(rule.occurrences(after: d("2026-01-31")) == [
            d("2026-02-28"), d("2026-03-29"), d("2026-03-30"), d("2026-03-31"),
        ])
    }

    @Test func monthlyLeapYear() {
        #expect(monthly([29], until: "2028-12-31").nextOccurrence(after: d("2028-01-29")) == d("2028-02-29"))
        #expect(monthly([30], until: "2028-12-31").nextOccurrence(after: d("2028-01-30")) == d("2028-02-29"))
        #expect(monthly([29], until: "2027-12-31").nextOccurrence(after: d("2027-01-29")) == d("2027-02-28"))
    }

    @Test func monthlySeveralDays() {
        let rule = monthly([1, 15], until: "2026-12-01")
        #expect(rule.occurrences(after: d("2026-10-15")) == [
            d("2026-11-01"), d("2026-11-15"), d("2026-12-01"),
        ])
    }

    @Test func monthlyCrossingYearEnd() {
        let rule = monthly([10, 31], until: "2027-02-15")
        #expect(rule.occurrences(after: d("2026-12-10")) == [
            d("2026-12-31"), d("2027-01-10"), d("2027-01-31"), d("2027-02-10"),
        ])
    }

    @Test func stopsAtEndDateInclusive() {
        let rule = weekly([.monday], until: "2026-10-12")
        #expect(rule.nextOccurrence(after: d("2026-10-05")) == d("2026-10-12"))
        #expect(rule.nextOccurrence(after: d("2026-10-12")) == nil)
        #expect(monthly([15], until: "2026-11-14").nextOccurrence(after: d("2026-10-15")) == nil)
    }

    @Test func emptyRuleHasNoOccurrences() {
        #expect(!weekly([], until: "2027-01-01").isValid)
        #expect(weekly([], until: "2027-01-01").nextOccurrence(after: d("2026-10-05")) == nil)
        #expect(!monthly([], until: "2027-01-01").isValid)
    }

    @Test func dueTodayOrOverdue() {
        let today = d("2026-10-06")
        func task(_ due: String?) -> TaskItem { TaskItem(title: "t", areaID: UUID(), dueDate: due.map(d)) }
        #expect(task("2026-10-05").isDueTodayOrOverdue(today: today))
        #expect(task("2026-10-06").isDueTodayOrOverdue(today: today))
        #expect(!task("2026-10-07").isDueTodayOrOverdue(today: today))
        #expect(!task(nil).isDueTodayOrOverdue(today: today))
        #expect(!task("2026-10-06").isOverdue(today: today))
    }

    @Test func lastOccurrenceIndicator() {
        var task = TaskItem(
            title: "Standup", areaID: UUID(), dueDate: d("2026-10-12"),
            recurrence: weekly([.monday], until: "2026-10-18"))
        #expect(task.isLastOccurrence)
        task.dueDate = d("2026-10-05")
        #expect(!task.isLastOccurrence)
    }
}
