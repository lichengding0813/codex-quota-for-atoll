import Foundation

struct ResetTracker {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func observe(_ window: QuotaWindow, now: Date = Date()) -> ResetObservation? {
        let prefix = "quota.\(window.id)"
        let storedLastReset = defaults.double(forKey: "\(prefix).lastResetAt")
        let inferredStart: Date? = {
            guard let reset = window.resetsAt,
                  let duration = window.windowDurationMinutes,
                  duration > 0
            else { return nil }
            return reset.addingTimeInterval(-TimeInterval(duration * 60))
        }()

        var observation: ResetObservation?
        if let inferredStart,
           inferredStart <= now.addingTimeInterval(300) {
            // The current window started exactly one window duration before its
            // next reset. This also follows reset-card use immediately, without
            // relying on the used percentage dropping between two app launches.
            defaults.set(inferredStart.timeIntervalSince1970, forKey: "\(prefix).lastResetAt")
            observation = ResetObservation(
                date: inferredStart,
                isEstimated: false
            )
        } else if storedLastReset > 0,
                  storedLastReset <= now.addingTimeInterval(300).timeIntervalSince1970 {
            observation = ResetObservation(
                date: Date(timeIntervalSince1970: storedLastReset),
                isEstimated: false
            )
        }

        if let reset = window.resetsAt?.timeIntervalSince1970 {
            defaults.set(reset, forKey: "\(prefix).resetsAt")
        }
        defaults.set(window.usedPercent, forKey: "\(prefix).usedPercent")
        return observation
    }
}
