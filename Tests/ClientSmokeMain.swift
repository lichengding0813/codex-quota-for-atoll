import Foundation

@main
struct ClientSmokeMain {
    static func main() async throws {
        let snapshot = try await CodexAppServerClient().fetchSnapshot()
        guard let primary = snapshot.primaryWindow else {
            fatalError("没有解析出主额度窗口")
        }
        guard (0...100).contains(primary.remainingPercent) else {
            fatalError("剩余额度超出合法范围")
        }

        let plan = snapshot.planType ?? "unknown"
        print("plan=\(plan)")
        print("window=\(primary.durationLabel)")
        print("used=\(primary.usedPercent)%")
        print("remaining=\(primary.remainingPercent)%")
        print("usageBucketsParsed=true")
    }
}
