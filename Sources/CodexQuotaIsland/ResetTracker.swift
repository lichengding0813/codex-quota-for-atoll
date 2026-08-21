import Foundation

struct ResetTracker {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func observe(_ window: QuotaWindow) -> ResetObservation? {
        let prefix = "quota.\(window.id)"
        let previousReset = defaults.double(forKey: "\(prefix).resetsAt")
        let previousUsed = defaults.object(forKey: "\(prefix).usedPercent") as? Int
        let storedLastReset = defaults.double(forKey: "\(prefix).lastResetAt")

        var observation: ResetObservation?
        if previousReset > 0,
           let reset = window.resetsAt?.timeIntervalSince1970,
           reset > previousReset + 60,
           let previousUsed,
           window.usedPercent < previousUsed {
            defaults.set(previousReset, forKey: "\(prefix).lastResetAt")
            observation = ResetObservation(
                date: Date(timeIntervalSince1970: previousReset),
                isEstimated: false
            )
        } else if storedLastReset > 0 {
            observation = ResetObservation(
                date: Date(timeIntervalSince1970: storedLastReset),
                isEstimated: false
            )
        } else if let reset = window.resetsAt,
                  let duration = window.windowDurationMinutes {
            observation = ResetObservation(
                date: reset.addingTimeInterval(-TimeInterval(duration * 60)),
                isEstimated: true
            )
        }

        if let reset = window.resetsAt?.timeIntervalSince1970 {
            defaults.set(reset, forKey: "\(prefix).resetsAt")
        }
        defaults.set(window.usedPercent, forKey: "\(prefix).usedPercent")
        return observation
    }
}
