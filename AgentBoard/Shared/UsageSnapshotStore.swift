import Foundation

enum UsageSnapshotStore {
    static func load() -> UsageSnapshot? {
        guard let url = cacheURL() else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(UsageSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    static func save(_ snapshot: UsageSnapshot) {
        guard let url = cacheURL() else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            assertionFailure("Failed to save usage snapshot: \(error.localizedDescription)")
        }
    }

    private static func cacheURL() -> URL? {
        if let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConfiguration.appGroupIdentifier
        ) {
            return sharedURL.appendingPathComponent(AppConfiguration.cacheFileName)
        }

        guard let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return supportURL
            .appendingPathComponent("AgentBoard", isDirectory: true)
            .appendingPathComponent(AppConfiguration.cacheFileName)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
