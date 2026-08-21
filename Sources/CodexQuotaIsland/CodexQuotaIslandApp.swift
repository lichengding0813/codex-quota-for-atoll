import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var previewWindow: NSWindow?
    private var acceptsTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let showsPreview = ProcessInfo.processInfo.arguments.contains("--preview-window")
        NSApplication.shared.setActivationPolicy(showsPreview ? .regular : .accessory)
        Task { @MainActor in
            await QuotaMonitor.shared.start()
        }

        // Control Center can send a visibility-driven terminate event while a
        // freshly signed MenuBarExtra is registering. Ignore only that brief
        // launch-time event; normal Quit and system termination work after it.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.acceptsTermination = true
        }

        if showsPreview {
            showPreviewWindow()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        acceptsTermination ? .terminateNow : .terminateCancel
    }

    private func showPreviewWindow() {
        let rootView = QuotaMenuView(monitor: QuotaMonitor.shared)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 392, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex 额度岛 · 预览"
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        previewWindow = window

        if let captureArgument = ProcessInfo.processInfo.arguments.first(
            where: { $0.hasPrefix("--capture=") }
        ) {
            let path = String(captureArgument.dropFirst("--capture=".count))
            Task { @MainActor in
                for _ in 0..<20 where QuotaMonitor.shared.snapshot == nil {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                capturePreview(window: window, path: path)
            }
        }
    }

    private func capturePreview(window: NSWindow, path: String) {
        guard let view = window.contentView,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

@main
struct CodexQuotaIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = QuotaMonitor.shared

    var body: some Scene {
        MenuBarExtra {
            QuotaMenuView(monitor: monitor)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "terminal.fill")
                if let remaining = monitor.snapshot?.primaryWindow?.remainingPercent {
                    Text("\(remaining)%")
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
