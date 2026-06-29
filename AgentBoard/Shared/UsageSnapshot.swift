import Foundation

struct UsageMetric: Codable, Equatable, Identifiable, Sendable {
    var id: String { label + value + (detail ?? "") }

    let label: String
    let value: String
    let detail: String?
}

struct UsageProgress: Codable, Equatable, Identifiable, Sendable {
    var id: String { label + current + limit + (resetTime ?? "") }

    let label: String
    let current: String
    let limit: String
    let fraction: Double
    let resetTime: String?

    init(label: String, current: String, limit: String, fraction: Double, resetTime: String? = nil) {
        self.label = label
        self.current = current
        self.limit = limit
        self.fraction = fraction
        self.resetTime = resetTime
    }
}

struct UsageSnapshot: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case placeholder
        case ready
        case missingAuthFile
        case authFileAccessNotGranted
        case missingAccessToken
        case unauthorized
        case requestFailed
        case noCachedData
    }

    let state: State
    let title: String
    let subtitle: String
    let fetchedAt: Date?
    let httpStatusCode: Int?
    let metrics: [UsageMetric]
    let progress: [UsageProgress]
    let resetCredits: [UsageMetric]?
    let errorMessage: String?
    let isStale: Bool

    var isReady: Bool {
        state == .ready
    }

    var resetCreditMetrics: [UsageMetric] {
        resetCredits ?? []
    }

    init(
        state: State,
        title: String,
        subtitle: String,
        fetchedAt: Date?,
        httpStatusCode: Int?,
        metrics: [UsageMetric],
        progress: [UsageProgress],
        resetCredits: [UsageMetric]? = nil,
        errorMessage: String?,
        isStale: Bool
    ) {
        self.state = state
        self.title = title
        self.subtitle = subtitle
        self.fetchedAt = fetchedAt
        self.httpStatusCode = httpStatusCode
        self.metrics = metrics
        self.progress = progress
        self.resetCredits = resetCredits
        self.errorMessage = errorMessage
        self.isStale = isStale
    }

    func withResetCredits(_ resetCredits: [UsageMetric]) -> UsageSnapshot {
        UsageSnapshot(
            state: state,
            title: title,
            subtitle: subtitle,
            fetchedAt: fetchedAt,
            httpStatusCode: httpStatusCode,
            metrics: metrics,
            progress: progress,
            resetCredits: resetCredits,
            errorMessage: errorMessage,
            isStale: isStale
        )
    }

    static var placeholder: UsageSnapshot {
        UsageSnapshot(
            state: .placeholder,
            title: "ChatGPT Usage",
            subtitle: "Waiting for usage data",
            fetchedAt: nil,
            httpStatusCode: nil,
            metrics: [
                UsageMetric(label: "Status", value: "Not loaded", detail: nil),
                UsageMetric(label: "Source", value: "~/.codex/auth.json", detail: nil)
            ],
            progress: [],
            resetCredits: [],
            errorMessage: nil,
            isStale: false
        )
    }

    static func failure(
        state: State,
        title: String = "ChatGPT Usage",
        subtitle: String,
        errorMessage: String? = nil,
        httpStatusCode: Int? = nil
    ) -> UsageSnapshot {
        UsageSnapshot(
            state: state,
            title: title,
            subtitle: subtitle,
            fetchedAt: Date(),
            httpStatusCode: httpStatusCode,
            metrics: [],
            progress: [],
            resetCredits: [],
            errorMessage: errorMessage,
            isStale: false
        )
    }

    func markedStale(reason: String) -> UsageSnapshot {
        UsageSnapshot(
            state: state,
            title: title,
            subtitle: reason,
            fetchedAt: fetchedAt,
            httpStatusCode: httpStatusCode,
            metrics: metrics,
            progress: progress,
            resetCredits: resetCredits,
            errorMessage: errorMessage,
            isStale: true
        )
    }
}
