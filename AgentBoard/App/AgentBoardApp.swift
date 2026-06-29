import AppKit
import SwiftUI

@main
struct AgentBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var refreshController = UsageRefreshController()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(refreshController)
                .frame(minWidth: 520, minHeight: 420)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Agent Board", systemImage: "sparkle") {
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
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
