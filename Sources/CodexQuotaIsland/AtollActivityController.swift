import AppKit
import AtollExtensionKit
import Darwin
import Foundation

@_silgen_name("bootstrap_look_up")
private func codexBootstrapLookUp(
    _ bootstrapPort: mach_port_t,
    _ serviceName: UnsafePointer<CChar>,
    _ servicePort: UnsafeMutablePointer<mach_port_t>
) -> kern_return_t

@MainActor
final class AtollActivityController {
    static let legacyActivityID = "codex-quota-main"
    static let experienceID = "codex-quota-card"
    static let minimumExtensionHostVersion = "2.3.0"
    static let machServiceName = "com.ebullioscopic.Atoll.xpc"

    private let client = AtollClient.shared
    private let monitorActionServer = CodexMonitorActionServer()
    private var hasPresentedExperience = false
    private var lastPresentedAt: Date?
    private var didDismissLegacyActivity = false

    var onAuthorizationChange: ((Bool) -> Void)?
    var onDismiss: (() -> Void)?
    var onRefreshMonitoring: (() async -> Void)?

    init() {
        client.onAuthorizationChange { [weak self] authorized in
            self?.onAuthorizationChange?(authorized)
        }
        client.onNotchExperienceDismiss(experienceID: Self.experienceID) { [weak self] in
            self?.hasPresentedExperience = false
            self?.onDismiss?()
        }
        monitorActionServer.onRefreshMonitoring = { [weak self] in
            await self?.onRefreshMonitoring?()
        }
    }

    var isInstalled: Bool {
        client.isAtollInstalled
    }

    var installedVersion: String? {
        guard let url = atollApplicationURL,
              let bundle = Bundle(url: url)
        else { return nil }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var compatibilityMessage: String? {
        guard let installedVersion else { return nil }
        if installedVersion.compare(
            Self.minimumExtensionHostVersion,
            options: .numeric
        ) == .orderedAscending {
            return "Atoll \(installedVersion) 缺少扩展服务，请升级到 \(Self.minimumExtensionHostVersion)+"
        }
        guard isMachServiceAvailable else {
            return "Atoll \(installedVersion) 未注册扩展服务，请启用兼容启动项"
        }
        return nil
    }

    var isMachServiceAvailable: Bool {
        var servicePort: mach_port_t = 0
        let result = Self.machServiceName.withCString { serviceName in
            codexBootstrapLookUp(bootstrap_port, serviceName, &servicePort)
        }
        guard result == KERN_SUCCESS, servicePort != MACH_PORT_NULL else { return false }
        mach_port_deallocate(mach_task_self_, servicePort)
        return true
    }

    func requestAuthorization() async throws -> Bool {
        try validateExtensionHost()
        return try await client.requestAuthorization()
    }

    func checkAuthorization() async throws -> Bool {
        try validateExtensionHost()
        return try await client.checkAuthorization()
    }

    func show(
        _ snapshot: QuotaSnapshot,
        codexConnected: Bool = true,
        monitoringEnabled: Bool = false,
        forcePresent: Bool = false
    ) async throws {
        try validateExtensionHost()
        guard let primary = snapshot.primaryWindow else { return }
        let actionURL = await monitorActionServer.start().map {
            monitorActionServer.endpointURL(port: $0)
        }
        let descriptor = makeDescriptor(
            snapshot: snapshot,
            window: primary,
            codexConnected: codexConnected,
            monitoringEnabled: monitoringEnabled,
            actionURL: actionURL
        )

        // 0.1.x used a compact Live Activity. Remove it once so this version is
        // represented only by Atoll's regular, swipeable extension tab.
        if !didDismissLegacyActivity {
            try? await client.dismissLiveActivity(activityID: Self.legacyActivityID)
            didDismissLegacyActivity = true
        }

        let shouldPresentAgain = forcePresent
            || !hasPresentedExperience
            || lastPresentedAt.map { Date().timeIntervalSince($0) > 43_200 } == true

        if shouldPresentAgain {
            do {
                try await client.presentNotchExperience(descriptor)
            } catch {
                // Atoll keeps extension cards across plugin relaunches. A new
                // process has no local presentation state, so presenting the
                // same ID can fail even though the existing card is updatable.
                try await client.updateNotchExperience(descriptor)
            }
            hasPresentedExperience = true
            lastPresentedAt = Date()
            return
        }

        do {
            try await client.updateNotchExperience(descriptor)
        } catch {
            try await client.presentNotchExperience(descriptor)
            hasPresentedExperience = true
            lastPresentedAt = Date()
        }
    }

    func dismiss() async throws {
        try validateExtensionHost()
        try await client.dismissNotchExperience(experienceID: Self.experienceID)
        hasPresentedExperience = false
    }

    func openAtoll() {
        guard let url = atollApplicationURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private var atollApplicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.Ebullioscopic.Atoll")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.ebullioscopic.Atoll")
            ?? URL(fileURLWithPath: "/Applications/Atoll.app")
    }

    private func validateExtensionHost() throws {
        if let compatibilityMessage {
            throw AtollHostError.incompatible(compatibilityMessage)
        }
    }

    private func makeDescriptor(
        snapshot: QuotaSnapshot,
        window: QuotaWindow,
        codexConnected: Bool,
        monitoringEnabled: Bool,
        actionURL: String?
    ) -> AtollNotchExperienceDescriptor {
        let remaining = window.remainingPercent
        let color = accentColor(for: remaining)
        let lastResetDate: String = {
            guard let observation = snapshot.lastReset else {
                return "暂无记录"
            }
            return formattedDate(observation.date)
        }()
        let plan = snapshot.planType?.uppercased() ?? "CODEX"
        let updatedAt = snapshot.fetchedAt.formatted(
            .dateTime.hour().minute().locale(Locale(identifier: "zh_CN"))
        )
        let compactCard = makeCompactCardHTML(
            remaining: remaining,
            plan: plan,
            sevenDays: snapshot.lastSevenDaysTokens.abbreviatedTokenCount,
            lifetime: snapshot.lifetimeTokens?.abbreviatedTokenCount ?? "—",
            nextReset: formattedDate(window.resetsAt),
            lastReset: lastResetDate,
            dailyUsage: snapshot.recentDailyUsage,
            updatedAt: updatedAt,
            codexConnected: codexConnected,
            monitoringEnabled: monitoringEnabled,
            actionURL: actionURL
        )

        return AtollNotchExperienceDescriptor(
            id: Self.experienceID,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.dinglicheng.CodexQuotaIsland",
            priority: remaining <= 10 ? .high : .normal,
            accentColor: color,
            metadata: [
                "usedPercent": "\(window.usedPercent)",
                "remainingPercent": "\(remaining)",
                "windowMinutes": "\(window.windowDurationMinutes ?? 0)",
                "surface": "extension-tab"
            ],
            tab: .init(
                title: "Codex 额度监控",
                iconSymbolName: "apple.intelligence",
                badgeIcon: .appIcon(
                    bundleIdentifier: "com.openai.codex",
                    size: CGSize(width: 28, height: 28),
                    cornerRadius: 8
                ),
                preferredHeight: 210,
                sections: [],
                webContent: .init(
                    html: compactCard,
                    preferredHeight: 92,
                    isTransparent: true,
                    allowLocalhostRequests: true,
                    maximumContentWidth: 640
                ),
                allowWebInteraction: true,
                footnote: nil
            )
        )
    }

    private func makeCompactCardHTML(
        remaining: Int,
        plan: String,
        sevenDays: String,
        lifetime: String,
        nextReset: String,
        lastReset: String,
        dailyUsage: [DailyTokenUsage],
        updatedAt: String,
        codexConnected: Bool,
        monitoringEnabled: Bool,
        actionURL: String?
    ) -> String {
        let accent = cssAccent(for: remaining)
        let connectionLabel = codexConnected ? "Codex 在线" : "Codex 离线"
        let connectionClass = codexConnected ? "online" : "offline"
        let buttonLabel = monitoringEnabled ? "刷新额度" : "启用额度监控"
        let buttonClass = monitoringEnabled ? "enabled" : ""
        let buttonDisabled = actionURL == nil ? "disabled" : ""
        let safeActionURL = escapeJavaScriptSingleQuoted(actionURL ?? "")
        let safe = [plan, sevenDays, lifetime, nextReset, lastReset, updatedAt, connectionLabel, buttonLabel]
            .map(escapeHTML)
        let heatmap = heatmapCellsHTML(for: dailyUsage)

        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        *{box-sizing:border-box}html,body{margin:0;width:100%;height:92px;overflow:hidden;background:transparent;color:#fff;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif}
        .card{height:92px;padding:6px 10px 7px;border:1px solid rgba(255,255,255,.075);border-radius:15px;background:rgba(255,255,255,.045);overflow:hidden}
        .top{height:22px;display:flex;align-items:flex-start;justify-content:flex-end}.controls{display:flex;align-items:center;justify-content:flex-end;gap:7px;white-space:nowrap;color:rgba(255,255,255,.48);font-size:7.5px}.state{display:flex;align-items:center;gap:3px}.dot{display:inline-block;width:4px;height:4px;border-radius:50%}.online,.atoll{background:#2ed18f}.offline{background:#ff5a5f}.sep{color:rgba(255,255,255,.18)}.updated{font-variant-numeric:tabular-nums;color:rgba(255,255,255,.38)}button{height:20px;padding:0 8px;border:1px solid rgba(46,209,143,.34);border-radius:7px;background:rgba(46,209,143,.13);color:#dfffee;font:600 8px/18px -apple-system,sans-serif;cursor:pointer}button:active{transform:scale(.98);background:rgba(46,209,143,.22)}button.enabled{border-color:rgba(46,209,143,.46);background:rgba(46,209,143,.16)}button:disabled{cursor:wait;opacity:.58}
        .data{height:57px;display:grid;grid-template-columns:3fr 1fr 1fr;gap:10px;align-items:stretch}.quota{display:flex;flex-direction:column;justify-content:center;padding-right:2px}.quota-head{display:flex;align-items:baseline;gap:7px}.pct{font:720 25px/26px ui-rounded,-apple-system,sans-serif;color:\(accent);letter-spacing:-.8px}.quota-label{font-size:8px;color:rgba(255,255,255,.42)}.bar{height:5px;margin:5px 0 4px;border-radius:9px;background:rgba(255,255,255,.13);overflow:hidden}.fill{height:100%;width:\(remaining)%;background:\(accent);border-radius:9px}.quota-foot{display:grid;grid-template-columns:auto 1fr 1fr;align-items:baseline;column-gap:13px;line-height:9px}.plan{font:650 8px/9px -apple-system,sans-serif;letter-spacing:.65px;color:rgba(255,255,255,.55)}.foot-metric{display:flex;align-items:baseline;justify-content:flex-end;gap:4px;white-space:nowrap}.foot-metric span{font-size:7.5px;color:rgba(255,255,255,.4)}.foot-metric b{font:650 8.5px/9px ui-monospace,"SF Mono",monospace;color:rgba(255,255,255,.72)}
        .heat,.reset{border-left:1px solid rgba(255,255,255,.08)}.heat{display:flex;align-items:center;justify-content:center;padding-left:8px}.heat-grid{display:grid;grid-template-columns:repeat(10,8px);grid-template-rows:repeat(3,8px);grid-auto-flow:row;gap:2px}.day{width:8px;height:8px;border-radius:2px;background:rgba(255,255,255,.07);box-shadow:inset 0 0 0 .5px rgba(255,255,255,.025)}.l1{background:#0e4429}.l2{background:#006d32}.l3{background:#26a641}.l4{background:#39d353}.reset{display:flex;flex-direction:column;justify-content:center;padding-left:10px}.row{display:flex;align-items:baseline;justify-content:space-between;gap:5px;line-height:23px;white-space:nowrap}.row span{font-size:7.5px;color:rgba(255,255,255,.43)}.row b{font-size:9px;font-weight:620;font-variant-numeric:tabular-nums}
        </style></head><body><div class="card">
          <div class="top"><div class="controls"><span class="state"><i class="dot \(connectionClass)"></i>\(safe[6])</span><span class="sep">·</span><span class="state"><i class="dot atoll"></i>Atoll 在线</span><span class="updated">更新 \(safe[5])</span><button id="monitor" class="\(buttonClass)" onclick="refreshMonitoring()" \(buttonDisabled)>\(safe[7])</button></div></div>
          <div class="data"><div class="quota"><div class="quota-head"><div class="pct">\(remaining)%</div><div class="quota-label">剩余额度</div></div><div class="bar"><div class="fill"></div></div><div class="quota-foot"><div class="plan">\(safe[0])</div><div class="foot-metric"><span>近7日</span><b>\(safe[1])</b></div><div class="foot-metric"><span>累计</span><b>\(safe[2])</b></div></div></div><div class="heat"><div class="heat-grid" aria-label="近 30 天 token 使用热力图">\(heatmap)</div></div><div class="reset"><div class="row"><span>上次</span><b>\(safe[4])</b></div><div class="row"><span>下次</span><b>\(safe[3])</b></div></div></div>
        <script>async function refreshMonitoring(){const b=document.getElementById('monitor');if(b.disabled)return;const first=!b.classList.contains('enabled');b.disabled=true;b.textContent=first?'正在启用…':'刷新中…';try{const r=await fetch('\(safeActionURL)',{cache:'no-store'});if(!r.ok)throw new Error();b.className='enabled';b.textContent='已刷新 ✓';setTimeout(()=>{b.disabled=false;b.textContent='刷新额度'},650)}catch(e){b.disabled=false;b.textContent=first?'启用失败，重试':'刷新失败，重试'}}</script>
        </div></body></html>
        """
    }

    private func heatmapCellsHTML(for usage: [DailyTokenUsage]) -> String {
        let peak = max(usage.map(\.tokens).max() ?? 0, 1)
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "M月d日"

        return usage.suffix(30).map { day in
            let level: Int
            if day.tokens <= 0 {
                level = 0
            } else {
                let ratio = log1p(Double(day.tokens)) / log1p(Double(peak))
                level = max(1, min(4, Int(ceil(ratio * 4))))
            }
            let detail = "\(dateFormatter.string(from: day.date)) · \(day.tokens.abbreviatedTokenCount) tokens"
            return "<i class=\"day l\(level)\" title=\"\(escapeHTML(detail))\"></i>"
        }.joined()
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func escapeJavaScriptSingleQuoted(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private func cssAccent(for remaining: Int) -> String {
        if remaining <= 20 { return "#ff4a4a" }
        if remaining <= 40 { return "#ff9f1f" }
        return "#2ed18f"
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "未知" }
        return date.formatted(
            .dateTime.month().day().hour().minute()
                .locale(Locale(identifier: "zh_CN"))
        )
    }

    private func accentColor(for remaining: Int) -> AtollColorDescriptor {
        if remaining <= 20 {
            return AtollColorDescriptor(red: 1.0, green: 0.25, blue: 0.25)
        }
        if remaining <= 40 {
            return AtollColorDescriptor(red: 1.0, green: 0.62, blue: 0.12)
        }
        return AtollColorDescriptor(red: 0.18, green: 0.82, blue: 0.56)
    }
}

private enum AtollHostError: LocalizedError {
    case incompatible(String)

    var errorDescription: String? {
        switch self {
        case let .incompatible(message): message
        }
    }
}
