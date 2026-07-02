import ServiceManagement
import SwiftUI
import WidgetKit

@MainActor
final class UsageRefreshController: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshotStore.load() ?? UsageSnapshot.placeholder
    @Published private(set) var isRefreshing = false
    @Published private(set) var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var launchAtLoginError: String?

    private var refreshTask: Task<Void, Never>?

    init() {
        startAutomaticRefresh()
    }

    deinit {
        refreshTask?.cancel()
    }

    func startAutomaticRefresh() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task { [weak self] in
            await self?.refreshUsage()

            while !Task.isCancelled {
                let interval = max(AppConfiguration.usageRefreshInterval, 1)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

                guard !Task.isCancelled else {
                    return
                }

                await self?.refreshUsage()
            }
        }
    }

    func refreshUsage() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        let nextSnapshot = await UsageService().fetchUsage()
        snapshot = nextSnapshot
        UsageSnapshotStore.save(nextSnapshot)
        forceReloadWidgetTimelines()

        isRefreshing = false
    }

    func replaceSnapshot(_ nextSnapshot: UsageSnapshot) {
        snapshot = nextSnapshot
        UsageSnapshotStore.save(nextSnapshot)
        forceReloadWidgetTimelines()
    }

    func reloadWidget() {
        forceReloadWidgetTimelines()
    }

    private func forceReloadWidgetTimelines() {
        reloadWidgetTimelines()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            reloadWidgetTimelines()
        }
    }

    private func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfiguration.widgetKind)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            if isEnabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }

            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }

        refreshLaunchAtLoginStatus()
    }
}
