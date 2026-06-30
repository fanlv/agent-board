import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = loadEntry()
        let nextRefresh = Date().addingTimeInterval(AppConfiguration.widgetTimelineRefreshInterval)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry() -> UsageEntry {
        let snapshot = UsageSnapshotStore.load() ?? UsageSnapshot.failure(
            state: .noCachedData,
            subtitle: "Open Agent Board to refresh",
            errorMessage: "WidgetKit cannot safely read ~/.codex/auth.json directly. The main app reads the token and writes a token-free usage snapshot for the widget."
        )

        return UsageEntry(date: Date(), snapshot: snapshot)
    }
}

struct AgentUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: UsageEntry

    var body: some View {
        ZStack {
            CircuitPattern(compact: family == .systemSmall)
            DecorativeTypeField(compact: family == .systemSmall)

            switch family {
            case .systemSmall:
                smallLayout
            case .systemMedium:
                mediumLayout
            default:
                largeLayout
            }
        }
        .containerBackground(for: .widget) {
            QuotaWidgetBackdrop()
        }
        .foregroundStyle(.white)
    }

    private var smallLayout: some View {
        mainGlassCard(compact: true)
    }

    private var mediumLayout: some View {
        mainGlassCard(compact: false)
    }

    private var largeLayout: some View {
        mainGlassCard(compact: false)
    }

    private func mainGlassCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 11) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.system(size: compact ? 12 : 15, weight: .bold))
                        .foregroundStyle(QuotaPalette.cardPrimary)

                    Text("Codex")
                        .font(.system(size: compact ? 18 : 22, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                }

                Spacer()

                Text(planText)
                    .font(.system(size: compact ? 11 : 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(QuotaPalette.cardMuted)
                    .lineLimit(1)
            }

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(primaryPercentText)
                    .font(.system(size: compact ? 36 : 54, weight: .heavy, design: .rounded))
                    .tracking(compact ? -0.4 : -1.0)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text("Used")
                    .font(.system(size: compact ? 12 : 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(QuotaPalette.cardMuted)
            }

            if !compact {
                Text(statusLabel)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(QuotaPalette.cardMuted)
                    .lineLimit(1)
            }

            VStack(spacing: compact ? 6 : 8) {
                quotaBar(title: "5小时窗口", progress: primaryProgress, tint: QuotaPalette.cardGreen)
                quotaBar(title: "7天窗口", progress: secondaryProgress, tint: QuotaPalette.cardBlue)
            }

            HStack(spacing: 10) {
                compactStat(label: "Reset", value: resetCreditValue)
                compactStat(label: "Expires", value: resetExpiryText(compact: compact))

                Spacer(minLength: 0)

                timestamp
            }
        }
        .padding(compact ? 16 : 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func quotaBar(title: String, progress: UsageProgress?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(QuotaPalette.cardMuted)

                Spacer()

                Text(progress.map(windowValue(for:)) ?? fallbackWindowValue)
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.16))

                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * CGFloat(progressRemainingFraction(progress)))
                }
            }
            .frame(height: 7)
        }
    }

    private func compactStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(QuotaPalette.cardMuted)

            Text(value)
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var timestamp: some View {
        Text(entry.snapshot.fetchedAt.map(Self.timeFormatter.string(from:)) ?? "Not updated")
            .font(.caption2)
            .foregroundStyle(QuotaPalette.cardMuted)
    }

    private var primaryProgress: UsageProgress? {
        entry.snapshot.progress.first
    }

    private var secondaryProgress: UsageProgress? {
        guard entry.snapshot.progress.count > 1 else {
            return nil
        }

        return entry.snapshot.progress[1]
    }

    private var primaryRemainingFraction: Double {
        guard let primaryProgress else {
            return entry.snapshot.isReady ? 0.5 : 0
        }

        return progressRemainingFraction(primaryProgress)
    }

    private var primaryPercentText: String {
        primaryProgress?.current ?? "\(Int(((1 - primaryRemainingFraction) * 100).rounded()))%"
    }

    private var primaryCaption: String {
        entry.snapshot.isReady ? "剩余" : statusText
    }

    private var fallbackWindowValue: String {
        entry.snapshot.isReady ? "等待接口字段" : statusText
    }

    private var statusLabel: String {
        switch entry.snapshot.state {
        case .ready:
            return entry.snapshot.subtitle
        case .placeholder:
            return "等待刷新"
        case .noCachedData:
            return "打开 Agent Board"
        case .authFileAccessNotGranted:
            return "需要授权 auth.json"
        case .missingAuthFile:
            return "未找到 auth.json"
        case .missingAccessToken:
            return "token 缺失"
        case .unauthorized:
            return "登录已过期"
        case .requestFailed:
            return "请求失败"
        }
    }

    private var statusColor: Color {
        switch entry.snapshot.state {
        case .ready:
            return Color(red: 0.24, green: 0.75, blue: 0.55)
        case .placeholder, .noCachedData:
            return Color(red: 0.95, green: 0.70, blue: 0.26)
        default:
            return Color(red: 0.96, green: 0.30, blue: 0.34)
        }
    }

    private var planText: String {
        let candidates = entry.snapshot.metrics.filter { metric in
            let label = metric.label.lowercased()
            let detail = metric.detail?.lowercased() ?? ""
            return label.contains("plan")
                || label.contains("tier")
                || label.contains("subscription")
                || detail.contains("plan")
                || detail.contains("tier")
                || detail.contains("subscription")
        }

        return candidates.first?.value.uppercased() ?? (entry.snapshot.isReady ? "未知" : statusText)
    }

    private var resetCreditMetric: UsageMetric? {
        let metrics = entry.snapshot.resetCreditMetrics
        return metrics.first { metric in
            let label = metric.label.lowercased()
            let detail = metric.detail?.lowercased() ?? ""
            return label.contains("可用")
                || label.contains("剩余")
                || label.contains("重置次数")
                || label.contains("remaining")
                || label.contains("available")
                || detail.contains("remaining")
                || detail.contains("available")
                || detail.contains("credit")
        } ?? metrics.first
    }

    private var resetCreditValue: String {
        resetCreditMetric?.value ?? (entry.snapshot.isReady ? "未知" : statusText)
    }

    private var resetExpiryMetrics: [UsageMetric] {
        entry.snapshot.resetCreditMetrics.filter { metric in
            metric.label.contains("过期") || (metric.detail?.contains("expires_at") ?? false)
        }
    }

    private func resetExpiryText(compact: Bool) -> String {
        let values = resetExpiryMetrics.map(\.value)
        guard !values.isEmpty else {
            return statusText
        }

        if compact {
            return values[0]
        }

        return values.prefix(2).joined(separator: " / ")
    }

    private func windowTitle(for progress: UsageProgress) -> String {
        let label = progress.label.lowercased()

        if label.contains("7") || label.contains("week") || label.contains("day") {
            return "7天窗口"
        }

        if label.contains("5") || label.contains("hour") {
            return "5小时窗口"
        }

        return progress.label
    }

    private func windowValue(for progress: UsageProgress) -> String {
        "剩余 \(remainingPercentText(for: progress))"
    }

    private func remainingPercentText(for progress: UsageProgress) -> String {
        "\(Int((progressRemainingFraction(progress) * 100).rounded()))%"
    }

    private func progressRemainingFraction(_ progress: UsageProgress?) -> Double {
        guard let progress else {
            return entry.snapshot.isReady ? 0.5 : 0
        }

        let usedFraction = max(0, min(1, progress.fraction))
        return 1 - usedFraction
    }

    private func cardBackground(emphasized: Bool) -> LinearGradient {
        LinearGradient(
            colors: emphasized
                ? [
                    Color(red: 0.99, green: 0.34, blue: 0.42).opacity(0.10),
                    QuotaPalette.solidPanel
                ]
                : [
                    QuotaPalette.solidPanel,
                    Color.white.opacity(0.88)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var statusText: String {
        switch entry.snapshot.state {
        case .ready:
            return "Ready"
        case .missingAuthFile:
            return "No auth"
        case .authFileAccessNotGranted:
            return "Grant"
        case .missingAccessToken:
            return "No token"
        case .unauthorized:
            return "Login"
        case .requestFailed:
            return "Failed"
        case .noCachedData:
            return "Open app"
        case .placeholder:
            return "Waiting"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private enum QuotaPalette {
    static let canvas = Color(red: 0.78, green: 0.96, blue: 0.90)
    static let warmCanvas = Color(red: 0.54, green: 0.78, blue: 0.94)
    static let ink = Color(red: 0.10, green: 0.105, blue: 0.10)
    static let secondaryInk = Color(red: 0.40, green: 0.40, blue: 0.36)
    static let mutedInk = Color(red: 0.55, green: 0.54, blue: 0.50)
    static let panel = Color(red: 0.95, green: 0.94, blue: 0.89)
    static let solidPanel = Color(red: 0.97, green: 0.96, blue: 0.91)
    static let hairline = Color(red: 0.16, green: 0.16, blue: 0.15).opacity(0.12)
    static let hotLine = Color(red: 0.96, green: 0.31, blue: 0.38).opacity(0.35)
    static let cardTop = Color(red: 0.37, green: 0.39, blue: 0.42).opacity(0.92)
    static let cardBottom = Color(red: 0.24, green: 0.27, blue: 0.30).opacity(0.94)
    static let cardMuted = Color(red: 0.90, green: 0.93, blue: 0.96)
    static let cardPrimary = Color(red: 0.76, green: 1.00, blue: 0.89)
    static let cardGreen = Color(red: 0.39, green: 0.86, blue: 0.76)
    static let cardBlue = Color(red: 0.39, green: 0.57, blue: 0.96)
}

private struct QuotaWidgetBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    QuotaPalette.cardTop,
                    QuotaPalette.cardBottom,
                    Color(red: 0.16, green: 0.20, blue: 0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.14),
                    .clear
                ],
                center: .topLeading,
                startRadius: 10,
                endRadius: 190
            )

            RadialGradient(
                colors: [
                    Color(red: 0.24, green: 0.68, blue: 0.78).opacity(0.18),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 220
            )
        }
    }
}

private struct CircuitPattern: View {
    let compact: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                circuitPath(in: geometry.size)
                    .stroke(
                        Color.white.opacity(0.16),
                        style: StrokeStyle(lineWidth: compact ? 1.2 : 1.6, lineCap: .round, lineJoin: .round)
                    )

                circuitPath(in: geometry.size)
                    .stroke(
                        Color(red: 0.22, green: 0.55, blue: 0.70).opacity(0.08),
                        style: StrokeStyle(lineWidth: compact ? 4 : 6, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 3)

                ForEach(Self.nodes.indices, id: \.self) { index in
                    let node = Self.nodes[index]
                    Circle()
                        .fill(index.isMultiple(of: 2) ? QuotaPalette.cardPrimary : Color.white.opacity(0.78))
                        .frame(width: compact ? node.size * 0.72 : node.size, height: compact ? node.size * 0.72 : node.size)
                        .shadow(color: QuotaPalette.cardPrimary.opacity(0.14), radius: 5, x: 0, y: 0)
                        .position(x: geometry.size.width * node.x, y: geometry.size.height * node.y)
                }

                RoundedRectangle(cornerRadius: compact ? 18 : 28, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: compact ? 18 : 28, style: .continuous)
                            .fill(.white.opacity(0.05))
                    )
                    .frame(width: geometry.size.width * 0.48, height: geometry.size.height * 0.30)
                    .position(x: geometry.size.width * 0.74, y: geometry.size.height * 0.20)
            }
        }
        .allowsHitTesting(false)
    }

    private func circuitPath(in size: CGSize) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.20))
        path.addLine(to: CGPoint(x: size.width * 0.30, y: size.height * 0.20))
        path.addLine(to: CGPoint(x: size.width * 0.44, y: size.height * 0.36))
        path.addLine(to: CGPoint(x: size.width * 0.74, y: size.height * 0.36))
        path.addLine(to: CGPoint(x: size.width * 0.90, y: size.height * 0.18))

        path.move(to: CGPoint(x: size.width * 0.14, y: size.height * 0.80))
        path.addLine(to: CGPoint(x: size.width * 0.30, y: size.height * 0.62))
        path.addLine(to: CGPoint(x: size.width * 0.56, y: size.height * 0.62))
        path.addLine(to: CGPoint(x: size.width * 0.70, y: size.height * 0.76))
        path.addLine(to: CGPoint(x: size.width * 0.92, y: size.height * 0.76))

        path.move(to: CGPoint(x: size.width * 0.06, y: size.height * 0.52))
        path.addLine(to: CGPoint(x: size.width * 0.22, y: size.height * 0.52))
        path.addLine(to: CGPoint(x: size.width * 0.32, y: size.height * 0.42))

        return path
    }

    private struct Node {
        let x: Double
        let y: Double
        let size: CGFloat
    }

    private static let nodes = [
        Node(x: 0.08, y: 0.20, size: 7),
        Node(x: 0.44, y: 0.36, size: 5),
        Node(x: 0.90, y: 0.18, size: 8),
        Node(x: 0.14, y: 0.80, size: 6),
        Node(x: 0.56, y: 0.62, size: 5),
        Node(x: 0.92, y: 0.76, size: 7)
    ]
}

private struct DecorativeTypeField: View {
    let compact: Bool

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(Self.fragments.enumerated()), id: \.offset) { _, fragment in
                Text(fragment.text)
                    .font(.system(size: compact ? fragment.size * 0.78 : fragment.size, weight: fragment.weight, design: .rounded))
                    .foregroundStyle(.white.opacity(fragment.opacity))
                    .rotationEffect(.degrees(fragment.rotation))
                    .position(
                        x: geometry.size.width * fragment.x,
                        y: geometry.size.height * fragment.y
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private struct Fragment {
        let text: String
        let x: Double
        let y: Double
        let size: CGFloat
        let opacity: Double
        let rotation: Double
        let weight: Font.Weight
    }

    private static let fragments = [
        Fragment(text: "TOTAL", x: 0.14, y: 0.18, size: 20, opacity: 0.018, rotation: -2, weight: .heavy),
        Fragment(text: "TOKENS", x: 0.82, y: 0.20, size: 18, opacity: 0.016, rotation: 5, weight: .bold),
        Fragment(text: "LIMITS", x: 0.18, y: 0.56, size: 18, opacity: 0.014, rotation: 7, weight: .semibold),
        Fragment(text: "RESET", x: 0.78, y: 0.66, size: 22, opacity: 0.016, rotation: -8, weight: .heavy),
        Fragment(text: "Σ", x: 0.48, y: 0.28, size: 42, opacity: 0.012, rotation: -8, weight: .black)
    ]
}

private struct GlossyQuotaBlob: View {
    let remainingFraction: Double
    let showsText: Bool

    var body: some View {
        ZStack {
            LiquidBlobShape()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.42, green: 0.46, blue: 0.45),
                            Color(red: 0.11, green: 0.13, blue: 0.12),
                            Color.black
                        ],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 128
                    )
                )
                .overlay(
                    LiquidBlobShape()
                        .stroke(.white.opacity(0.22), lineWidth: 1.4)
                )
                .shadow(color: .black.opacity(0.24), radius: 20, x: 0, y: 12)

            Circle()
                .fill(.white.opacity(0.30))
                .frame(width: 50, height: 28)
                .blur(radius: 6)
                .offset(x: -28, y: -34)
                .rotationEffect(.degrees(-26))

            LiquidBlobShape()
                .trim(from: max(0, 1 - remainingFraction), to: 1)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.78, blue: 0.72),
                            Color(red: 0.99, green: 0.30, blue: 0.38)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(86))
                .padding(7)

            if showsText {
                VStack(spacing: -2) {
                    Text("\(Int((remainingFraction * 100).rounded()))%")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)

                    Text("剩余")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
    }
}

private struct LiquidBlobShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        path.move(to: CGPoint(x: rect.minX + width * 0.50, y: rect.minY + height * 0.05))
        path.addCurve(
            to: CGPoint(x: rect.minX + width * 0.96, y: rect.minY + height * 0.40),
            control1: CGPoint(x: rect.minX + width * 0.75, y: rect.minY - height * 0.02),
            control2: CGPoint(x: rect.minX + width * 0.98, y: rect.minY + height * 0.15)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + width * 0.74, y: rect.minY + height * 0.92),
            control1: CGPoint(x: rect.minX + width * 1.05, y: rect.minY + height * 0.64),
            control2: CGPoint(x: rect.minX + width * 0.94, y: rect.minY + height * 0.82)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + width * 0.23, y: rect.minY + height * 0.88),
            control1: CGPoint(x: rect.minX + width * 0.54, y: rect.minY + height * 1.03),
            control2: CGPoint(x: rect.minX + width * 0.34, y: rect.minY + height * 0.98)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + width * 0.06, y: rect.minY + height * 0.38),
            control1: CGPoint(x: rect.minX + width * 0.05, y: rect.minY + height * 0.73),
            control2: CGPoint(x: rect.minX - width * 0.02, y: rect.minY + height * 0.54)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + width * 0.50, y: rect.minY + height * 0.05),
            control1: CGPoint(x: rect.minX + width * 0.09, y: rect.minY + height * 0.13),
            control2: CGPoint(x: rect.minX + width * 0.28, y: rect.minY + height * 0.08)
        )
        path.closeSubpath()

        return path
    }
}

private struct MiniMetricChip: View {
    let metric: UsageMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(QuotaPalette.secondaryInk)
                .lineLimit(1)

            Text(metric.value)
                .font(.caption.weight(.heavy))
                .foregroundStyle(QuotaPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.44), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(QuotaPalette.hairline, lineWidth: 1)
        )
    }
}

@main
struct AgentUsageWidget: Widget {
    let kind = AppConfiguration.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            AgentUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex 额度")
        .description("显示本地 Codex 登录的 ChatGPT 用量。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
