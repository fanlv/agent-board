import AppKit
import SwiftUI

@main
struct AgentBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var refreshController = UsageRefreshController()
    @State private var windowController: AgentBoardWindowController?

    var body: some Scene {
        MenuBarExtra {
            Button("Open Agent Board") {
                openMainWindow()
            }

            Button(refreshController.isRefreshing ? "Refreshing..." : "Refresh Now") {
                Task {
                    await refreshController.refreshUsage()
                }
            }
            .disabled(refreshController.isRefreshing)

            Button("Reload Widget") {
                refreshController.reloadWidget()
            }

            Divider()

            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { refreshController.launchAtLoginEnabled },
                    set: { refreshController.setLaunchAtLoginEnabled($0) }
                )
            )

            if let launchAtLoginError = refreshController.launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
            }

            Divider()

            Button("Quit Agent Board") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "chart.bar.fill")
                .accessibilityLabel("Agent Board")
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Usage") {
                    Task {
                        await refreshController.refreshUsage()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(refreshController.isRefreshing)
            }
        }
    }

    private func openMainWindow() {
        if windowController == nil {
            windowController = AgentBoardWindowController(refreshController: refreshController)
        }

        windowController?.show()
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class AgentBoardWindowController: NSObject, NSWindowDelegate {
    private let refreshController: UsageRefreshController
    private var window: NSWindow?

    init(refreshController: UsageRefreshController) {
        self.refreshController = refreshController
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let contentView = ContentView()
            .environmentObject(refreshController)
            .frame(minWidth: 520, minHeight: 420)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Agent Board"
        window.contentView = NSHostingView(rootView: contentView)
        window.minSize = NSSize(width: 520, height: 420)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
