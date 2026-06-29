import Foundation

enum UsageResponseParser {
    private struct ScalarNode {
        let path: [String]
        let value: JSONValue
    }

    static func snapshot(from data: Data, fetchedAt: Date, httpStatusCode: Int) throws -> UsageSnapshot {
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        if let snapshot = structuredUsageSnapshot(from: root, fetchedAt: fetchedAt, httpStatusCode: httpStatusCode) {
            return snapshot
        }

        let scalars = flatten(root)
        let metrics = chooseMetrics(from: scalars)
        let progress = Array(collectProgress(from: root).prefix(3))
        let subtitle = makeSubtitle(from: scalars, fetchedAt: fetchedAt)

        return UsageSnapshot(
            state: .ready,
            title: "ChatGPT Usage",
            subtitle: subtitle,
            fetchedAt: fetchedAt,
            httpStatusCode: httpStatusCode,
            metrics: metrics.isEmpty ? fallbackMetrics(from: root, byteCount: data.count) : metrics,
            progress: progress,
            errorMessage: nil,
            isStale: false
        )
    }

    private static func structuredUsageSnapshot(
        from root: JSONValue,
        fetchedAt: Date,
        httpStatusCode: Int
    ) -> UsageSnapshot? {
        guard case .object(let object) = root else {
            return nil
        }

        let email = stringValue(object["email"])
        let planType = stringValue(object["plan_type"])
        var metrics: [UsageMetric] = []

        if let email {
            metrics.append(UsageMetric(label: "Email", value: email, detail: nil))
        }

        if let planType {
            metrics.append(UsageMetric(label: "Plan Type", value: planType, detail: nil))
        }

        var progress: [UsageProgress] = []
        if case .object(let rateLimit)? = object["rate_limit"] {
            if let primary = windowProgress(from: rateLimit["primary_window"], label: "5小时窗口") {
                progress.append(primary)
            }

            if let secondary = windowProgress(from: rateLimit["secondary_window"], label: "7天窗口") {
                progress.append(secondary)
            }
        }

        guard !metrics.isEmpty || !progress.isEmpty else {
            return nil
        }

        return UsageSnapshot(
            state: .ready,
            title: "Codex 额度",
            subtitle: email ?? "Updated \(timeFormatter.string(from: fetchedAt))",
            fetchedAt: fetchedAt,
            httpStatusCode: httpStatusCode,
            metrics: metrics,
            progress: progress,
            errorMessage: nil,
            isStale: false
        )
    }

    private static func windowProgress(from value: JSONValue?, label: String) -> UsageProgress? {
        guard case .object(let object)? = value,
              let usedPercent = object["used_percent"]?.numberValue else {
            return nil
        }

        let usedText = "\(JSONValue.number(usedPercent).displayValue)%"
        let resetTime = object["reset_at"].flatMap(parseDate(from:)).map(resetTimeDescription(for:))

        return UsageProgress(
            label: label,
            current: usedText,
            limit: resetTime.map { "重置 \($0)" } ?? "重置未知",
            fraction: min(max(usedPercent / 100, 0), 1),
            resetTime: resetTime
        )
    }

    static func resetCreditMetrics(from data: Data) throws -> [UsageMetric] {
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        var metrics: [UsageMetric] = []

        if case .object(let object) = root {
            if let availableCount = object["available_count"] {
                metrics.append(
                    UsageMetric(
                        label: "可用重置",
                        value: availableCount.displayValue,
                        detail: "available_count"
                    )
                )
            }

            if case .array(let credits)? = object["credits"] {
                if object["available_count"] == nil {
                    let availableCredits = credits.filter { credit in
                        guard case .object(let creditObject) = credit else {
                            return false
                        }
                        return stringValue(creditObject["status"]) == "available"
                    }

                    metrics.append(
                        UsageMetric(
                            label: "可用重置",
                            value: "\(availableCredits.count)",
                            detail: "credits.status"
                        )
                    )
                }

                var expirationIndex = 0
                for credit in credits {
                    guard case .object(let creditObject) = credit else {
                        continue
                    }

                    if let status = stringValue(creditObject["status"]), status != "available" {
                        continue
                    }

                    guard let expiresAt = creditObject["expires_at"],
                          let expirationDate = parseDate(from: expiresAt) else {
                        continue
                    }

                    expirationIndex += 1
                    metrics.append(
                        UsageMetric(
                            label: "机会 \(expirationIndex) 过期",
                            value: compactDateTimeDescription(for: expirationDate),
                            detail: nil
                        )
                    )
                }
            }
        }

        if !metrics.isEmpty {
            return deduplicate(metrics)
        }

        return fallbackMetrics(from: root, byteCount: data.count).map { metric in
            UsageMetric(
                label: "重置次数",
                value: metric.value,
                detail: metric.detail ?? "rate-limit-reset-credits"
            )
        }
    }

    private static func flatten(_ value: JSONValue, path: [String] = []) -> [ScalarNode] {
        switch value {
        case .object(let object):
            return object.keys.sorted().flatMap { key in
                flatten(object[key] ?? .null, path: path + [key])
            }
        case .array(let values):
            return values.enumerated().flatMap { index, value in
                flatten(value, path: path + ["\(index)"])
            }
        case .string, .number, .bool, .null:
            return [ScalarNode(path: path, value: value)]
        }
    }

    private static func chooseMetrics(from scalars: [ScalarNode]) -> [UsageMetric] {
        let safeScalars = scalars.filter { node in
            let path = node.path.joined(separator: ".").lowercased()
            return !path.contains("token")
                && !path.contains("secret")
                && !path.contains("authorization")
                && node.value.displayValue.count <= 80
        }

        let candidates = safeScalars
            .filter { node in
                let path = node.path.joined(separator: ".").lowercased()
                return priorityKeywords.contains { path.contains($0) }
            }
            .sorted { lhs, rhs in
                priorityScore(lhs.path) < priorityScore(rhs.path)
            }

        return Array(candidates.prefix(8)).map { node in
            UsageMetric(
                label: displayName(for: node.path),
                value: node.value.displayValue,
                detail: detailPath(for: node.path)
            )
        }
    }

    private static func fallbackMetrics(from root: JSONValue, byteCount: Int) -> [UsageMetric] {
        var metrics = [
            UsageMetric(label: "Response", value: "\(byteCount) bytes", detail: nil)
        ]

        switch root {
        case .object(let object):
            metrics.append(UsageMetric(label: "Fields", value: "\(object.count)", detail: nil))
        case .array(let values):
            metrics.append(UsageMetric(label: "Items", value: "\(values.count)", detail: nil))
        default:
            break
        }

        return metrics
    }

    private static func collectProgress(from value: JSONValue, path: [String] = []) -> [UsageProgress] {
        switch value {
        case .object(let object):
            var results: [UsageProgress] = []
            let numericFields = object.compactMap { key, value -> (String, Double)? in
                guard let number = value.numberValue else {
                    return nil
                }
                return (key, number)
            }

            if let progress = progressMetric(from: numericFields, path: path) {
                results.append(progress)
            }

            for key in object.keys.sorted() {
                results.append(contentsOf: collectProgress(from: object[key] ?? .null, path: path + [key]))
            }

            return deduplicate(results)
        case .array(let values):
            return values.enumerated().flatMap { index, value in
                collectProgress(from: value, path: path + ["\(index)"])
            }
        case .string, .number, .bool, .null:
            return []
        }
    }

    private static func progressMetric(
        from numericFields: [(String, Double)],
        path: [String]
    ) -> UsageProgress? {
        guard !numericFields.isEmpty else {
            return nil
        }

        let used = firstNumber(in: numericFields, matching: ["used", "usage", "current", "consumed", "spent"])
        let limit = firstNumber(in: numericFields, matching: ["limit", "cap", "quota", "max", "total"])
        let remaining = firstNumber(in: numericFields, matching: ["remaining", "left", "available"])

        let currentValue: Double?
        let limitValue: Double?

        if let used, let limit {
            currentValue = used
            limitValue = limit
        } else if let remaining, let limit {
            currentValue = max(0, limit - remaining)
            limitValue = limit
        } else {
            currentValue = nil
            limitValue = nil
        }

        guard let currentValue, let limitValue, limitValue > 0 else {
            return nil
        }

        let fraction = min(max(currentValue / limitValue, 0), 1)
        return UsageProgress(
            label: displayName(for: path.isEmpty ? ["usage"] : path),
            current: JSONValue.number(currentValue).displayValue,
            limit: JSONValue.number(limitValue).displayValue,
            fraction: fraction
        )
    }

    private static func firstNumber(
        in fields: [(String, Double)],
        matching keywords: [String]
    ) -> Double? {
        fields
            .first { field in
                let key = field.0.lowercased()
                return keywords.contains { key.contains($0) }
            }?
            .1
    }

    private static func deduplicate(_ progress: [UsageProgress]) -> [UsageProgress] {
        var seen = Set<String>()
        return progress.filter { item in
            let key = "\(item.label)-\(item.current)-\(item.limit)"
            guard !seen.contains(key) else {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private static func deduplicate(_ metrics: [UsageMetric]) -> [UsageMetric] {
        var seen = Set<String>()
        return metrics.filter { item in
            let key = "\(item.label)-\(item.value)-\(item.detail ?? "")"
            guard !seen.contains(key) else {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private static func makeSubtitle(from scalars: [ScalarNode], fetchedAt: Date) -> String {
        if let plan = firstScalar(in: scalars, matching: ["plan", "tier", "subscription"]) {
            return "\(displayName(for: plan.path)): \(plan.value.displayValue)"
        }

        if let reset = firstScalar(in: scalars, matching: ["reset", "expires", "renew"]) {
            return "\(displayName(for: reset.path)): \(reset.value.displayValue)"
        }

        return "Updated \(timeFormatter.string(from: fetchedAt))"
    }

    private static func firstScalar(
        in scalars: [ScalarNode],
        matching keywords: [String]
    ) -> ScalarNode? {
        scalars.first { node in
            let path = node.path.joined(separator: ".").lowercased()
            return !path.contains("token")
                && keywords.contains { path.contains($0) }
                && node.value.displayValue.count <= 80
        }
    }

    private static func displayName(for path: [String]) -> String {
        let meaningful = path.reversed().first { component in
            Int(component) == nil
        } ?? path.last ?? "Value"

        let withSpaces = meaningful
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let words = splitCamelCase(withSpaces)

        return words
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func detailPath(for path: [String]) -> String? {
        guard path.count > 1 else {
            return nil
        }

        return path.joined(separator: ".")
    }

    private static func splitCamelCase(_ value: String) -> String {
        value.reduce(into: "") { result, character in
            if character.isUppercase, !result.isEmpty, result.last != " " {
                result.append(" ")
            }
            result.append(character)
        }
    }

    private static func priorityScore(_ path: [String]) -> Int {
        let joined = path.joined(separator: ".").lowercased()
        return priorityKeywords.firstIndex { joined.contains($0) } ?? priorityKeywords.count
    }

    private static func resetCreditDisplayName(for path: [String]) -> String {
        let joined = path.joined(separator: ".").lowercased()

        if joined.contains("remaining") || joined.contains("available") || joined.contains("left") {
            return "剩余重置"
        }

        if joined.contains("used") || joined.contains("consumed") {
            return "已用重置"
        }

        if joined.contains("total") || joined.contains("limit") || joined.contains("max") {
            return "重置上限"
        }

        if joined.contains("reset") || joined.contains("next") || joined.contains("time") || joined.contains("_at") {
            return "下次重置"
        }

        if joined.contains("credit") || joined.contains("count") {
            return "重置次数"
        }

        return displayName(for: path)
    }

    private static func resetCreditPriorityScore(_ path: [String]) -> Int {
        let joined = path.joined(separator: ".").lowercased()
        return resetCreditKeywords.firstIndex { joined.contains($0) } ?? resetCreditKeywords.count
    }

    private static func firstResetCreditScalar(
        in scalars: [ScalarNode],
        matching keywords: [String]
    ) -> ScalarNode? {
        scalars
            .filter { node in
                let path = node.path.joined(separator: ".").lowercased()
                return !isIgnoredResetCreditPath(path)
                    && keywords.contains { path.contains($0) }
                    && node.value.displayValue != "null"
                    && node.value.displayValue.count <= 40
            }
            .sorted { lhs, rhs in
                resetCreditPriorityScore(lhs.path) < resetCreditPriorityScore(rhs.path)
            }
            .first
    }

    private static func nearestResetCreditDate(
        in scalars: [ScalarNode],
        matching keywords: [String]
    ) -> (date: Date, path: [String])? {
        scalars
            .compactMap { node -> (date: Date, path: [String])? in
                let path = node.path.joined(separator: ".").lowercased()
                guard !isIgnoredResetCreditPath(path),
                      keywords.contains(where: { path.contains($0) }),
                      let date = parseDate(from: node.value) else {
                    return nil
                }
                return (date, node.path)
            }
            .filter { $0.date >= Date().addingTimeInterval(-60) }
            .sorted { $0.date < $1.date }
            .first
    }

    private static func isIgnoredResetCreditPath(_ path: String) -> Bool {
        path.contains("token")
            || path.contains("secret")
            || path.contains("authorization")
            || path.contains("description")
            || path.contains("profile_image")
            || path.contains("image_url")
            || path.contains("avatar")
            || path.contains(".id")
            || path.hasSuffix("id")
            || path.contains("granted_at")
            || path.contains("created_at")
            || path.contains("updated_at")
    }

    private static func parseDate(from value: JSONValue) -> Date? {
        switch value {
        case .string(let string):
            return parseISO8601Date(string)
        case .number(let number):
            let seconds = number > 10_000_000_000 ? number / 1_000 : number
            return Date(timeIntervalSince1970: seconds)
        default:
            return nil
        }
    }
    private static func stringValue(_ value: JSONValue?) -> String? {
        guard case .string(let string)? = value else {
            return nil
        }

        return string
    }


    private static func parseISO8601Date(_ value: String) -> Date? {
        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractionalSeconds.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        return nil
    }

    private static func relativeTimeDescription(for date: Date) -> String {
        let interval = Int(date.timeIntervalSinceNow.rounded())

        guard interval > 0 else {
            return "已到期"
        }

        let days = interval / 86_400
        let hours = (interval % 86_400) / 3_600
        let minutes = (interval % 3_600) / 60

        if days > 0 {
            return hours > 0 ? "\(days)天\(hours)小时后" : "\(days)天后"
        }

        if hours > 0 {
            return minutes > 0 ? "\(hours)小时\(minutes)分钟后" : "\(hours)小时后"
        }

        return "\(max(minutes, 1))分钟后"
    }

    private static func absoluteDateTimeDescription(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func compactDateTimeDescription(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func resetTimeDescription(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static let priorityKeywords = [
        "plan",
        "tier",
        "subscription",
        "used",
        "usage",
        "remaining",
        "limit",
        "quota",
        "cap",
        "credit",
        "message",
        "request",
        "reset",
        "period",
        "window",
        "expire",
        "model"
    ]

    private static let resetCreditKeywords = [
        "remaining",
        "available",
        "left",
        "credit",
        "credits",
        "count",
        "reset",
        "resets",
        "used",
        "consumed",
        "total",
        "limit",
        "max",
        "next",
        "time",
        "_at"
    ]

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
