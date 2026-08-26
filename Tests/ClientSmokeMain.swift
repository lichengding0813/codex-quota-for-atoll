import Foundation

@main
struct ClientSmokeMain {
    static func main() async throws {
        let snapshot = try await CodexAppServerClient().fetchSnapshot()
        guard let quotaWindow = snapshot.quotaWindow else {
            fatalError("没有解析出额度窗口")
        }
        guard (0...100).contains(quotaWindow.remainingPercent) else {
            fatalError("剩余额度超出合法范围")
        }

        let plan = snapshot.planType ?? "unknown"
        print("plan=\(plan)")
        if let shortTermWindow = snapshot.shortTermWindow {
            print("shortTermWindow=\(shortTermWindow.durationLabel)")
            print("shortTermRemaining=\(shortTermWindow.remainingPercent)%")
        }
        print("quotaWindow=\(quotaWindow.durationLabel)")
        print("quotaRemaining=\(quotaWindow.remainingPercent)%")
        print("usageBucketsParsed=true")
    }
}
