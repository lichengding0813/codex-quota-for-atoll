import XCTest
@testable import CodexQuotaIsland

final class ResetTrackerTests: XCTestCase {
    func testUsesCurrentWindowStartAfterAResetCardChangesTheSchedule() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tracker = ResetTracker(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let durationMinutes: Int64 = 10_080
        let nextReset = now.addingTimeInterval(TimeInterval(durationMinutes * 60))
        let window = QuotaWindow(
            id: "codex-primary",
            limitID: "codex",
            name: "codex",
            usedPercent: 42,
            windowDurationMinutes: durationMinutes,
            resetsAt: nextReset
        )

        let result = try XCTUnwrap(tracker.observe(window, now: now))

        XCTAssertEqual(result.date.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(result.isEstimated, false)
    }

    func testRepairsAFutureStoredResetFromTheCurrentWindow() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(now.addingTimeInterval(6 * 86_400).timeIntervalSince1970,
                     forKey: "quota.codex-primary.lastResetAt")
        let durationMinutes: Int64 = 10_080
        let expectedStart = now.addingTimeInterval(-2 * 3_600)
        let window = QuotaWindow(
            id: "codex-primary",
            limitID: "codex",
            name: "codex",
            usedPercent: 12,
            windowDurationMinutes: durationMinutes,
            resetsAt: expectedStart.addingTimeInterval(TimeInterval(durationMinutes * 60))
        )

        let result = try XCTUnwrap(ResetTracker(defaults: defaults).observe(window, now: now))

        XCTAssertEqual(result.date.timeIntervalSince1970, expectedStart.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(
            defaults.double(forKey: "quota.codex-primary.lastResetAt"),
            expectedStart.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testFallsBackToAValidStoredResetWhenDurationIsUnavailable() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let stored = now.addingTimeInterval(-86_400)
        defaults.set(stored.timeIntervalSince1970, forKey: "quota.codex-primary.lastResetAt")
        let window = QuotaWindow(
            id: "codex-primary",
            limitID: "codex",
            name: "codex",
            usedPercent: 40,
            windowDurationMinutes: nil,
            resetsAt: nil
        )

        let result = try XCTUnwrap(ResetTracker(defaults: defaults).observe(window, now: now))

        XCTAssertEqual(result.date.timeIntervalSince1970, stored.timeIntervalSince1970, accuracy: 0.001)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "ResetTrackerTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
