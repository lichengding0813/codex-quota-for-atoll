import AppKit
import SwiftUI

@MainActor
enum AppTerminationController {
    private(set) static var allowsTermination = false

    static func requestQuit() {
        allowsTermination = true
        NSApplication.shared.terminate(nil)
    }

    static func allowSystemTermination() {
        allowsTermination = true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var previewWindow: NSWindow?
    private var powerOffObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let showsPreview = ProcessInfo.processInfo.arguments.contains("--preview-window")
        NSApplication.shared.setActivationPolicy(showsPreview ? .regular : .accessory)
        Task { @MainActor in
            await QuotaMonitor.shared.start()
        }

        // A hidden MenuBarExtra can receive a visibility-driven termination
        // request from Control Center. Keep the monitor alive for its loopback
        // card action, while still allowing an explicit Quit and system poweroff.
        powerOffObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppTerminationController.allowSystemTermination()
            }
        }

        if showsPreview {
            showPreviewWindow()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppTerminationController.allowsTermination ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let powerOffObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(powerOffObserver)
        }
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
                if let remaining = monitor.snapshot?.quotaWindow?.remainingPercent {
                    Text("\(remaining)%")
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
