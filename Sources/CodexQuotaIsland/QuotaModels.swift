import Foundation

struct RateLimitWindowPayload: Decodable, Sendable {
    let usedPercent: Int
    let windowDurationMins: Int64?
    let resetsAt: Int64?
}

struct RateLimitSnapshotPayload: Decodable, Sendable {
    let limitId: String?
    let limitName: String?
    let primary: RateLimitWindowPayload?
    let secondary: RateLimitWindowPayload?
    let planType: String?
    let rateLimitReachedType: String?
}

struct RateLimitsPayload: Decodable, Sendable {
    let rateLimits: RateLimitSnapshotPayload
    let rateLimitsByLimitId: [String: RateLimitSnapshotPayload]?
}

struct UsageSummaryPayload: Decodable, Sendable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSec: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?
}

struct DailyUsageBucketPayload: Decodable, Sendable {
    let startDate: String
    let tokens: Int64
}

struct UsagePayload: Decodable, Sendable {
    let summary: UsageSummaryPayload?
    let dailyUsageBuckets: [DailyUsageBucketPayload]?
}

struct QuotaWindow: Identifiable, Sendable, Equatable {
    let id: String
    let limitID: String
    let name: String
    let usedPercent: Int
    let windowDurationMinutes: Int64?
    let resetsAt: Date?

    var remainingPercent: Int {
        min(max(100 - usedPercent, 0), 100)
    }

    var durationLabel: String {
        guard let minutes = windowDurationMinutes else { return "额度窗口" }
        if minutes % 10_080 == 0 {
            let weeks = minutes / 10_080
            return weeks == 1 ? "7 天额度" : "\(weeks) 周额度"
        }
        if minutes % 1_440 == 0 {
            return "\(minutes / 1_440) 天额度"
        }
        if minutes % 60 == 0 {
            return "\(minutes / 60) 小时额度"
        }
        return "\(minutes) 分钟额度"
    }
}

struct ResetObservation: Sendable, Equatable {
    let date: Date
    let isEstimated: Bool
}

struct QuotaSnapshot: Sendable, Equatable {
    let planType: String?
    let windows: [QuotaWindow]
    let todayTokens: Int64
    let lastSevenDaysTokens: Int64
    let lifetimeTokens: Int64?
    let fetchedAt: Date
    var lastReset: ResetObservation?

    var primaryWindow: QuotaWindow? {
        windows.first(where: { $0.limitID == "codex" && $0.id.hasSuffix("primary") })
            ?? windows.min(by: { $0.remainingPercent < $1.remainingPercent })
    }

    static func make(
        rateLimits: RateLimitsPayload,
        usage: UsagePayload?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuotaSnapshot {
        let snapshots: [(String, RateLimitSnapshotPayload)]
        if let byID = rateLimits.rateLimitsByLimitId, !byID.isEmpty {
            snapshots = byID.sorted(by: { $0.key < $1.key })
        } else {
            snapshots = [(rateLimits.rateLimits.limitId ?? "codex", rateLimits.rateLimits)]
        }

        var windows: [QuotaWindow] = []
        for (fallbackID, snapshot) in snapshots {
            let limitID = snapshot.limitId ?? fallbackID
            let baseName = snapshot.limitName?.isEmpty == false ? snapshot.limitName! : limitID
            if let primary = snapshot.primary {
                windows.append(
                    QuotaWindow(
                        id: "\(limitID)-primary",
                        limitID: limitID,
                        name: baseName,
                        usedPercent: primary.usedPercent,
                        windowDurationMinutes: primary.windowDurationMins,
                        resetsAt: primary.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    )
                )
            }
            if let secondary = snapshot.secondary {
                windows.append(
                    QuotaWindow(
                        id: "\(limitID)-secondary",
                        limitID: limitID,
                        name: "\(baseName) · 次级",
                        usedPercent: secondary.usedPercent,
                        windowDurationMinutes: secondary.windowDurationMins,
                        resetsAt: secondary.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    )
                )
            }
        }

        let isoDay = DateFormatter.isoDay
        let startOfToday = calendar.startOfDay(for: now)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        var todayTokens: Int64 = 0
        var lastSevenDaysTokens: Int64 = 0
        for bucket in usage?.dailyUsageBuckets ?? [] {
            guard let date = isoDay.date(from: bucket.startDate) else { continue }
            if calendar.isDate(date, inSameDayAs: now) {
                todayTokens += bucket.tokens
            }
            if date >= sevenDaysAgo && date <= now {
                lastSevenDaysTokens += bucket.tokens
            }
        }

        return QuotaSnapshot(
            planType: snapshots.lazy.compactMap { $0.1.planType }.first,
            windows: windows,
            todayTokens: todayTokens,
            lastSevenDaysTokens: lastSevenDaysTokens,
            lifetimeTokens: usage?.summary?.lifetimeTokens,
            fetchedAt: now,
            lastReset: nil
        )
    }
}

extension DateFormatter {
    static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension Int64 {
    var abbreviatedTokenCount: String {
        let value = Double(self)
        if value >= 1_000_000_000 {
            return String(format: "%.2fB", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.2fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return "\(self)"
    }
}
