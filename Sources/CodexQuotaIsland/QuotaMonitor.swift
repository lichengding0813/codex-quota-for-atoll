import AppKit
import Foundation

@MainActor
final class QuotaMonitor: ObservableObject {
    static let shared = QuotaMonitor()
    private static let monitoringEnabledKey = "monitoring.enabled"

    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var codexStatus = "等待首次刷新"
    @Published private(set) var codexConnected = false
    @Published private(set) var monitoringEnabled: Bool
    @Published private(set) var atollStatus = "正在连接 Atoll"
    @Published private(set) var atollAuthorized = false
    @Published private(set) var atollCardVisible = false
    @Published private(set) var lastError: String?

    private let codexClient = CodexAppServerClient()
    private let resetTracker = ResetTracker()
    private let atoll = AtollActivityController()
    private var refreshLoop: Task<Void, Never>?
    private var started = false

    private init() {
        let defaults = UserDefaults.standard
        if let savedValue = defaults.object(forKey: Self.monitoringEnabledKey) as? Bool {
            monitoringEnabled = savedValue
        } else {
            // Migrate existing installations whose in-memory opt-in was lost
            // whenever the menu-bar process was relaunched.
            monitoringEnabled = true
            defaults.set(true, forKey: Self.monitoringEnabledKey)
        }

        atoll.onAuthorizationChange = { [weak self] authorized in
            guard let self else { return }
            self.atollAuthorized = authorized
            self.atollStatus = authorized ? "Atoll 已授权" : "需要 Atoll 授权"
            if authorized, let snapshot = self.snapshot {
                Task { @MainActor in
                    await self.publishToAtoll(
                        snapshot,
                        codexConnected: self.codexConnected,
                        forcePresent: true
                    )
                }
            }
        }
        atoll.onDismiss = { [weak self] in
            self?.atollCardVisible = false
            self?.atollStatus = "Atoll 翻页卡片已被关闭"
        }
        atoll.onRefreshMonitoring = { [weak self] in
            await self?.activateOrRefreshMonitoring()
        }
    }

    deinit {
        refreshLoop?.cancel()
    }

    func start() async {
        guard !started else { return }
        started = true
        await refresh(requestAuthorizationIfNeeded: true)
        if monitoringEnabled {
            startRefreshLoop()
        }
    }

    func refresh(requestAuthorizationIfNeeded: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        do {
            var newSnapshot = try await codexClient.fetchSnapshot()
            if let primary = newSnapshot.primaryWindow {
                newSnapshot.lastReset = resetTracker.observe(primary)
            }
            snapshot = newSnapshot
            codexConnected = true
            codexStatus = "已于 \(newSnapshot.fetchedAt.formatted(date: .omitted, time: .shortened)) 更新"
            await connectAtoll(
                snapshot: newSnapshot,
                requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
            )
        } catch {
            codexConnected = false
            codexStatus = "Codex 数据不可用"
            lastError = error.localizedDescription
            if let snapshot, atollAuthorized {
                await publishToAtoll(snapshot, codexConnected: false)
            }
        }
    }

    func requestAtollAuthorization() async {
        if let message = atoll.compatibilityMessage {
            atollStatus = message
            lastError = message
            return
        }

        do {
            atoll.openAtoll()
            let authorized = try await atoll.requestAuthorization()
            atollAuthorized = authorized
            atollStatus = authorized ? "Atoll 已授权" : "请在 Atoll 设置中授权"
            if authorized, let snapshot {
                await publishToAtoll(
                    snapshot,
                    codexConnected: codexConnected,
                    forcePresent: true
                )
            }
        } catch {
            atollStatus = "Atoll 连接失败"
            lastError = error.localizedDescription
        }
    }

    func showAtollCardAgain() async {
        guard let snapshot else { return }
        await publishToAtoll(
            snapshot,
            codexConnected: codexConnected,
            forcePresent: true
        )
    }

    func dismissAtollCard() async {
        do {
            try await atoll.dismiss()
            atollCardVisible = false
            atollStatus = "Atoll 翻页卡片已关闭"
        } catch {
            lastError = error.localizedDescription
        }
    }

    func openAtoll() {
        atoll.openAtoll()
    }

    func activateOrRefreshMonitoring() async {
        if !monitoringEnabled {
            monitoringEnabled = true
            UserDefaults.standard.set(true, forKey: Self.monitoringEnabledKey)
            startRefreshLoop()
        }

        // A card click can arrive while launch-time or menu-bar refresh work is
        // still running. Wait for that request and then perform the user's
        // explicit refresh instead of silently discarding the click.
        while isRefreshing {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        await refresh()
    }

    private func startRefreshLoop() {
        refreshLoop?.cancel()
        refreshLoop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval: UInt64 = self.codexConnected
                    ? 60_000_000_000
                    : 15_000_000_000
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    private func connectAtoll(
        snapshot: QuotaSnapshot,
        requestAuthorizationIfNeeded: Bool
    ) async {
        guard atoll.isInstalled else {
            atollStatus = "未找到 Atoll"
            return
        }

        if let message = atoll.compatibilityMessage {
            atollStatus = message
            return
        }

        do {
            var authorized = try await atoll.checkAuthorization()
            if !authorized, requestAuthorizationIfNeeded {
                atoll.openAtoll()
                authorized = try await atoll.requestAuthorization()
            }
            atollAuthorized = authorized
            guard authorized else {
                atollStatus = "请在 Atoll 设置中授权"
                return
            }
            await publishToAtoll(snapshot, codexConnected: codexConnected)
        } catch {
            atollStatus = "Atoll 连接失败"
            lastError = error.localizedDescription
        }
    }

    private func publishToAtoll(
        _ snapshot: QuotaSnapshot,
        codexConnected: Bool,
        forcePresent: Bool = false
    ) async {
        do {
            try await atoll.show(
                snapshot,
                codexConnected: codexConnected,
                monitoringEnabled: monitoringEnabled,
                forcePresent: forcePresent
            )
            atollAuthorized = true
            atollCardVisible = true
            atollStatus = "Atoll 翻页卡片正在显示"
        } catch {
            atollCardVisible = false
            atollStatus = "Atoll 翻页卡片发布失败"
            lastError = error.localizedDescription
        }
    }
}
