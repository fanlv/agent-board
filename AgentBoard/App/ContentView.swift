import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

struct ContentView: View {
    @State private var snapshot = UsageSnapshotStore.load() ?? .placeholder
    @State private var isRefreshing = false

    private let refreshTimer = Timer.publish(every: AppConfiguration.usageRefreshInterval, on: .main, in: .common).autoconnect()
    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !snapshot.progress.isEmpty {
                    progressSection
                }

                if !snapshot.resetCreditMetrics.isEmpty {
                    resetCreditsSection
                }

                metricsSection

                if let errorMessage = snapshot.errorMessage {
                    errorSection(errorMessage)
                }

                footer
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        .task {
            await refreshUsage()
        }
        .onReceive(refreshTimer) { _ in
            Task {
                await refreshUsage()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))

                Text(snapshot.subtitle)
                    .foregroundStyle(.secondary)

                if let fetchedAt = snapshot.fetchedAt {
                    Text("Last updated \(Self.dateFormatter.string(from: fetchedAt))")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    Task {
                        await refreshUsage()
                    }
                } label: {
                    Label(isRefreshing ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)

                Button {
                    WidgetCenter.shared.reloadAllTimelines()
                } label: {
                    Label("Reload Widget", systemImage: "rectangle.3.group")
                }
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Usage")
                .font(.headline)

            ForEach(snapshot.progress) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.label)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("已用 \(item.current) · \(item.limit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: item.fraction)
                        .progressViewStyle(.linear)
                }
                .padding(14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fields")
                .font(.headline)

            if snapshot.metrics.isEmpty {
                Text("No usage fields available yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(snapshot.metrics) { metric in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(metric.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(metric.value)
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            if let detail = metric.detail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    private var resetCreditsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reset Credits")
                .font(.headline)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(snapshot.resetCreditMetrics) { metric in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(metric.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(metric.value)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)

                        if let detail = metric.detail {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)

            if snapshot.state == .authFileAccessNotGranted || snapshot.state == .missingAuthFile {
                Button("Grant auth.json Access") {
                    grantAuthFileAccess()
                }
            }

            Button("Show auth.json in Finder") {
                revealAuthFile()
            }
        }
        .padding(16)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private var footer: some View {
        HStack {
            Text("Token source: ~/.codex/auth.json")
                .font(.footnote)
                .foregroundStyle(.tertiary)

            Spacer()

            if let statusCode = snapshot.httpStatusCode {
                Text("HTTP \(statusCode)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @MainActor
    private func refreshUsage() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        let nextSnapshot = await UsageService().fetchUsage()
        snapshot = nextSnapshot

        if nextSnapshot.isReady {
            WidgetCenter.shared.reloadTimelines(ofKind: AppConfiguration.widgetKind)
        }

        isRefreshing = false
    }

    private func revealAuthFile() {
        let authURL = AuthFileBookmarkStore.defaultAuthURL

        if FileManager.default.fileExists(atPath: authURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([authURL])
            return
        }

        let codexDirectory = authURL.deletingLastPathComponent()
        NSWorkspace.shared.open(codexDirectory)
    }

    private func grantAuthFileAccess() {
        let authURL = AuthFileBookmarkStore.defaultAuthURL
        let panel = NSOpenPanel()
        panel.title = "Grant Access to auth.json"
        panel.message = "Select ~/.codex/auth.json so Agent Board can read your Codex access token."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = authURL.deletingLastPathComponent()
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        do {
            try AuthFileBookmarkStore.saveBookmark(for: selectedURL)
            Task {
                await refreshUsage()
            }
        } catch {
            snapshot = UsageSnapshot.failure(
                state: .authFileAccessNotGranted,
                subtitle: "Could not save file access",
                errorMessage: error.localizedDescription
            )
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
