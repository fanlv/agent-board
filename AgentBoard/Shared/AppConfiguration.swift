import Foundation

enum AppConfiguration {
    static let appGroupIdentifier = "9BQ563P4RA.com.fanlv.AgentBoard"
    static let usageEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let resetCreditsEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
    static let authRelativePath = ".codex/auth.json"
    static let cacheFileName = "usage-snapshot.json"
    static let widgetKind = "AgentUsageWidget.remaining"
    static let usageRefreshInterval: TimeInterval = 60
    static let widgetTimelineRefreshInterval: TimeInterval = 60
}
