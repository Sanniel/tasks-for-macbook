import Foundation
import Testing
@testable import TasksCore

@Suite struct LocalDateTests {
    @Test func parsesAndFormatsISO() throws {
        let date = try #require(LocalDate(isoString: "2026-03-07"))
        #expect(date.year == 2026 && date.month == 3 && date.day == 7)
        #expect(date.isoString == "2026-03-07")
    }

    @Test(arguments: ["2026-02-29", "2026-13-01", "2026-00-10", "2026-04-31", "26-01-01",
                      "2026-1-01", "2026-01-01T00:00", "", "abcd-ef-gh"])
    func rejectsInvalid(_ string: String) {
        #expect(LocalDate(isoString: string) == nil)
    }

    @Test func leapDays() {
        #expect(LocalDate(isoString: "2024-02-29") != nil)
        #expect(LocalDate(isoString: "2000-02-29") != nil)
        #expect(LocalDate(isoString: "1900-02-29") == nil)
    }

    @Test func ordering() throws {
        let a = try #require(LocalDate(isoString: "2025-12-31"))
        let b = try #require(LocalDate(isoString: "2026-01-01"))
        #expect(a < b)
    }

    @Test func convertsFromDateInGivenTimeZone() throws {
        // 2026-01-01T23:30Z is still Jan 1 in UTC but Jan 2 in Helsinki (UTC+2).
        let instant = Date(timeIntervalSince1970: 1_767_310_200)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var helsinki = Calendar(identifier: .gregorian)
        helsinki.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        #expect(LocalDate(instant, calendar: utc).isoString == "2026-01-01")
        #expect(LocalDate(instant, calendar: helsinki).isoString == "2026-01-02")
    }

    @Test func codesAsPlainString() throws {
        let date = try #require(LocalDate(isoString: "2026-10-05"))
        let json = String(decoding: try JSONEncoder().encode([date]), as: UTF8.self)
        #expect(json == #"["2026-10-05"]"#)
        #expect(try JSONDecoder().decode([LocalDate].self, from: Data(json.utf8)) == [date])
    }
}

@Suite struct RecurrenceRuleCodingTests {
    private func encode(_ rule: RecurrenceRule) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(rule), as: UTF8.self)
    }

    @Test func weeklyJSON() throws {
        let rule = RecurrenceRule(
            pattern: .weekly(weekdays: [.thursday, .monday]),
            endDate: LocalDate(isoString: "2026-12-31")!)
        let json = try encode(rule)
        #expect(json == #"{"endDate":"2026-12-31","type":"weekly","weekdays":[1,4]}"#)
        #expect(try JSONDecoder().decode(RecurrenceRule.self, from: Data(json.utf8)) == rule)
    }

    @Test func monthlyJSON() throws {
        let rule = RecurrenceRule(
            pattern: .monthly(days: [31, 1, 15]), endDate: LocalDate(isoString: "2027-06-30")!)
        let json = try encode(rule)
        #expect(json == #"{"days":[1,15,31],"endDate":"2027-06-30","type":"monthly"}"#)
        #expect(try JSONDecoder().decode(RecurrenceRule.self, from: Data(json.utf8)) == rule)
    }

    @Test func rejectsInvalidMonthDay() {
        let json = #"{"days":[0,15],"endDate":"2027-06-30","type":"monthly"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RecurrenceRule.self, from: Data(json.utf8))
        }
    }
}

@Suite struct PriorityTests {
    @Test func storedValues() {
        #expect(Priority.allCases.map(\.rawValue) == [-1, 0, 1, 2, 3])
        #expect(TaskItem(title: "x", areaID: UUID()).priority == .normal)
        #expect(Priority.urgent > Priority.high)
    }
}
