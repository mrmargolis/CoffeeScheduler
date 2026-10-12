import Foundation
import Testing

@testable import CoffeeCore

@Suite struct DateUtilsTests {
    @Test func addDaysAcrossMonthAndYear() {
        #expect(DateUtils.addDays("2026-01-31", 1) == "2026-02-01")
        #expect(DateUtils.addDays("2025-12-31", 1) == "2026-01-01")
        #expect(DateUtils.addDays("2024-02-28", 1) == "2024-02-29")
        #expect(DateUtils.addDays("2026-03-01", -1) == "2026-02-28")
    }

    @Test func daysBetween() {
        #expect(DateUtils.daysBetween("2026-01-01", "2026-01-31") == 30)
        #expect(DateUtils.daysBetween("2026-01-31", "2026-01-01") == -30)
    }

    @Test func dateRangeIsInclusive() {
        #expect(DateUtils.dateRange("2026-02-27", "2026-03-01") == ["2026-02-27", "2026-02-28", "2026-03-01"])
        #expect(DateUtils.dateRange("2026-03-01", "2026-02-27").isEmpty)
    }

    @Test func addMonthsClampsDay() {
        #expect(DateUtils.addMonths("2026-01-31", 1) == "2026-02-28")
        #expect(DateUtils.addMonths("2026-11-15", 2) == "2027-01-15")
        #expect(DateUtils.addMonths("2026-03-15", -3) == "2025-12-15")
    }

    @Test func firstOfMonth() {
        #expect(DateUtils.firstOfMonth("2026-02-17") == "2026-02-01")
    }

    @Test func rejectsMalformed() {
        #expect(DateUtils.dayNumber("2026-13-01") == nil)
        #expect(DateUtils.dayNumber("not a date") == nil)
    }

    @Test func noonUTCIsTheSameDayInUTC() {
        #expect(DateUtils.noonUTC("2024-02-01") == Date(timeIntervalSince1970: 1_706_788_800))
        for day in ["1999-12-31", "2026-03-29", "2026-10-25"] {
            #expect(DateUtils.isoString(DateUtils.noonUTC(day), timeZone: TimeZone(identifier: "UTC")!) == day)
        }
    }

    @Test func isoStringUsesTimeZone() {
        let date = Date(timeIntervalSince1970: 1_706_788_800)  // 2024-02-01 12:00 UTC
        #expect(DateUtils.isoString(date, timeZone: TimeZone(identifier: "UTC")!) == "2024-02-01")
        #expect(DateUtils.isoString(date, timeZone: TimeZone(identifier: "Pacific/Kiritimati")!) == "2024-02-02")
    }
}
