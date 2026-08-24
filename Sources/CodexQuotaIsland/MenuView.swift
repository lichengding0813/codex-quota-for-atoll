import SwiftUI

struct QuotaMenuView: View {
    @ObservedObject var monitor: QuotaMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let snapshot = monitor.snapshot,
               let primary = snapshot.primaryWindow {
                quotaCard(snapshot: snapshot, primary: primary)
                usageGrid(snapshot: snapshot)
                statusSection
            } else {
                loadingState
            }

            if let error = monitor.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            controls
        }
        .padding(16)
        .frame(width: 360)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.85), .cyan.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black.opacity(0.8))
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Codex")
                    .font(.subheadline.weight(.semibold))
                Text(monitor.snapshot?.planType?.uppercased() ?? "CODEX")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()
            if monitor.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func quotaCard(snapshot: QuotaSnapshot, primary: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("剩余额度")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(primary.remainingPercent)%")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color(for: primary.remainingPercent))
            }

            ProgressView(value: Double(primary.remainingPercent), total: 100)
                .progressViewStyle(.linear)
                .tint(color(for: primary.remainingPercent))

            HStack {
                Label(primary.durationLabel, systemImage: "clock.arrow.circlepath")
                Spacer()
                Text("已使用 \(primary.usedPercent)%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            infoRow(
                title: "下次重置",
                value: primary.resetsAt?.formatted(
                    .dateTime.month().day().weekday(.abbreviated).hour().minute()
                        .locale(Locale(identifier: "zh_CN"))
                ) ?? "未知"
            )

            if let lastReset = snapshot.lastReset {
                infoRow(
                    title: "上次重置",
                    value: lastReset.date.formatted(
                        .dateTime.month().day().hour().minute()
                            .locale(Locale(identifier: "zh_CN"))
                    )
                )
            }
        }
        .padding(14)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func usageGrid(snapshot: QuotaSnapshot) -> some View {
        HStack(spacing: 10) {
            metric(title: "近 7 天", value: snapshot.lastSevenDaysTokens.abbreviatedTokenCount, icon: "calendar")
            metric(
                title: "累计",
                value: snapshot.lifetimeTokens?.abbreviatedTokenCount ?? "—",
                icon: "sum"
            )
        }
    }

    private func metric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusRow(
                text: monitor.codexStatus,
                color: monitor.codexConnected ? .green : .orange
            )
            statusRow(
                text: monitor.atollStatus,
                color: monitor.atollCardVisible ? .green : (monitor.atollAuthorized ? .yellow : .orange)
            )
            statusRow(
                text: monitor.monitoringEnabled ? "额度监控已启用" : "额度监控未启用",
                color: monitor.monitoringEnabled ? .green : .gray
            )
        }
        .font(.caption)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(monitor.codexStatus)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task { await monitor.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .disabled(monitor.isRefreshing)

                Button {
                    Task { await monitor.showAtollCardAgain() }
                } label: {
                    Label("显示到 Atoll", systemImage: "rectangle.topthird.inset.filled")
                        .frame(maxWidth: .infinity)
                }
                .disabled(monitor.snapshot == nil || !monitor.atollAuthorized)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await monitor.activateOrRefreshMonitoring() }
                } label: {
                    Label(
                        monitor.isRefreshing
                            ? "刷新中…"
                            : (monitor.monitoringEnabled ? "刷新额度" : "启用额度监控"),
                        systemImage: monitor.monitoringEnabled ? "arrow.clockwise.circle.fill" : "waveform.path.ecg"
                    )
                        .frame(maxWidth: .infinity)
                }
                .disabled(monitor.isRefreshing)

                Button {
                    Task { await monitor.requestAtollAuthorization() }
                } label: {
                    Label("授权 Atoll", systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    monitor.openAtoll()
                } label: {
                    Label("打开 Atoll", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
            }

            HStack {
                Button("关闭 Atoll 卡片") {
                    Task { await monitor.dismissAtollCard() }
                }
                .disabled(!monitor.atollCardVisible)
                Spacer()
                Button("退出") {
                    AppTerminationController.requestQuit()
                }
            }
            .font(.caption)
            .buttonStyle(.link)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func statusRow(text: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private func color(for remaining: Int) -> Color {
        if remaining <= 20 { return .red }
        if remaining <= 40 { return .orange }
        return .green
    }
}
