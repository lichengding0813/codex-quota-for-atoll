import XCTest
@testable import CodexQuotaIsland

final class QuotaModelTests: XCTestCase {
    func testBuildsWeeklyQuotaAndUsage() throws {
        let json = """
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": null,
            "primary": {"usedPercent": 37, "windowDurationMins": 10080, "resetsAt": 1787836933},
            "secondary": null,
            "planType": "plus",
            "rateLimitReachedType": null
          },
          "rateLimitsByLimitId": null
        }
        """
        let usageJSON = """
        {
          "summary": {"lifetimeTokens": 1000000},
          "dailyUsageBuckets": [
            {"startDate": "2026-08-20", "tokens": 1200},
            {"startDate": "2026-08-21", "tokens": 3400}
          ]
        }
        """
        let decoder = JSONDecoder()
        let rates = try decoder.decode(RateLimitsPayload.self, from: Data(json.utf8))
        let usage = try decoder.decode(UsagePayload.self, from: Data(usageJSON.utf8))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = DateFormatter.isoDay.date(from: "2026-08-21")!.addingTimeInterval(12 * 3600)
        let snapshot = QuotaSnapshot.make(rateLimits: rates, usage: usage, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.primaryWindow?.remainingPercent, 63)
        XCTAssertEqual(snapshot.primaryWindow?.durationLabel, "7 天额度")
        XCTAssertEqual(snapshot.todayTokens, 3_400)
        XCTAssertEqual(snapshot.lastSevenDaysTokens, 4_600)
        XCTAssertEqual(snapshot.lifetimeTokens, 1_000_000)
        XCTAssertEqual(snapshot.recentDailyUsage.count, 30)
        XCTAssertEqual(snapshot.recentDailyUsage.first?.tokens, 0)
        XCTAssertEqual(snapshot.recentDailyUsage.suffix(2).map(\.tokens), [1_200, 3_400])
        XCTAssertTrue(calendar.isDate(snapshot.recentDailyUsage.last!.date, inSameDayAs: now))
    }

    func testNormalizesSparseAndDuplicateDailyUsage() throws {
        let ratesJSON = """
        {
          "rateLimits": {
            "limitId": "codex", "limitName": null, "primary": null,
            "secondary": null, "planType": "plus", "rateLimitReachedType": null
          },
          "rateLimitsByLimitId": null
        }
        """
        let usageJSON = """
        {
          "summary": null,
          "dailyUsageBuckets": [
            {"startDate": "2026-08-19", "tokens": 100},
            {"startDate": "2026-08-19", "tokens": 250},
            {"startDate": "2026-08-21", "tokens": 700},
            {"startDate": "2026-07-01", "tokens": 9999}
          ]
        }
        """
        let decoder = JSONDecoder()
        let rates = try decoder.decode(RateLimitsPayload.self, from: Data(ratesJSON.utf8))
        let usage = try decoder.decode(UsagePayload.self, from: Data(usageJSON.utf8))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = DateFormatter.isoDay.date(from: "2026-08-21")!.addingTimeInterval(12 * 3600)

        let snapshot = QuotaSnapshot.make(rateLimits: rates, usage: usage, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.recentDailyUsage.count, 30)
        XCTAssertEqual(snapshot.recentDailyUsage.suffix(3).map(\.tokens), [350, 0, 700])
        XCTAssertEqual(snapshot.recentDailyUsage.map(\.tokens).reduce(0, +), 1_050)
    }

    func testClampsRemainingPercentage() {
        let tooHigh = QuotaWindow(
            id: "x-primary",
            limitID: "x",
            name: "x",
            usedPercent: 130,
            windowDurationMinutes: nil,
            resetsAt: nil
        )
        let negative = QuotaWindow(
            id: "y-primary",
            limitID: "y",
            name: "y",
            usedPercent: -20,
            windowDurationMinutes: nil,
            resetsAt: nil
        )

        XCTAssertEqual(tooHigh.remainingPercent, 0)
        XCTAssertEqual(negative.remainingPercent, 100)
    }
}
