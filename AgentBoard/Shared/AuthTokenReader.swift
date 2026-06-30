import Foundation

enum AuthTokenReaderError: LocalizedError {
    case missingAuthFile(URL)
    case accessNotGranted(URL, String)
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case .missingAuthFile(let url):
            return "Auth file was not found at \(url.path)"
        case .accessNotGranted(let url, let reason):
            return "Access was not granted for \(url.path): \(reason)"
        case .missingAccessToken:
            return "tokens.access_token was not found in auth.json"
        }
    }
}

enum AuthFileBookmarkStore {
    static let defaultAuthURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(AppConfiguration.authRelativePath)

    private static let bookmarkKey = "authFileBookmark"

    static func bookmarkedAuthURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                try? saveBookmark(for: url)
            }

            return url
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return nil
        }
    }

    static func saveBookmark(for url: URL) throws {
        let didStartSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }
}

struct AuthTokenReader {
    private struct CodexAuth: Decodable {
        let tokens: Tokens?
    }

    private struct Tokens: Decodable {
        let accessToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }

    func accessToken() throws -> String {
        guard let url = AuthFileBookmarkStore.bookmarkedAuthURL() else {
            throw AuthTokenReaderError.accessNotGranted(
                AuthFileBookmarkStore.defaultAuthURL,
                "No saved file permission bookmark."
            )
        }

        let didStartSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if Self.isMissingFileError(error) {
                throw AuthTokenReaderError.missingAuthFile(AuthFileBookmarkStore.defaultAuthURL)
            }

            throw AuthTokenReaderError.accessNotGranted(
                AuthFileBookmarkStore.defaultAuthURL,
                error.localizedDescription
            )
        }

        let auth = try JSONDecoder().decode(CodexAuth.self, from: data)
        let token = auth.tokens?.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let token, !token.isEmpty else {
            throw AuthTokenReaderError.missingAccessToken
        }

        return token
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain
            && nsError.code == NSFileReadNoSuchFileError
    }
}
