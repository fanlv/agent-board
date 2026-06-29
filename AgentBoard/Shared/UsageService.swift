import Foundation

struct UsageService {
    private let authTokenReader: AuthTokenReader
    private let urlSession: URLSession

    init(
        authTokenReader: AuthTokenReader = AuthTokenReader(),
        urlSession: URLSession = .shared
    ) {
        self.authTokenReader = authTokenReader
        self.urlSession = urlSession
    }

    func fetchUsage() async -> UsageSnapshot {
        let accessToken: String

        do {
            accessToken = try authTokenReader.accessToken()
        } catch AuthTokenReaderError.missingAuthFile {
            return UsageSnapshot.failure(
                state: .missingAuthFile,
                subtitle: "Missing ~/.codex/auth.json",
                errorMessage: "Run Codex login first, then refresh Agent Board."
            )
        } catch AuthTokenReaderError.accessNotGranted(_, let reason) {
            return UsageSnapshot.failure(
                state: .authFileAccessNotGranted,
                subtitle: "Grant access to auth.json",
                errorMessage: "macOS sandbox needs one-time access to ~/.codex/auth.json. Click Grant auth.json Access and select that file. Reason: \(reason)"
            )
        } catch AuthTokenReaderError.missingAccessToken {
            return UsageSnapshot.failure(
                state: .missingAccessToken,
                subtitle: "Missing tokens.access_token",
                errorMessage: "~/.codex/auth.json exists, but tokens.access_token is empty."
            )
        } catch {
            return UsageSnapshot.failure(
                state: .requestFailed,
                subtitle: "Could not read auth.json",
                errorMessage: error.localizedDescription
            )
        }

        do {
            return try await fetchUsage(accessToken: accessToken)
        } catch UsageRequestError.unauthorized(let statusCode) {
            return UsageSnapshot.failure(
                state: .unauthorized,
                subtitle: "Token was rejected",
                errorMessage: "The usage API returned HTTP \(statusCode). Re-login with Codex and refresh.",
                httpStatusCode: statusCode
            )
        } catch UsageRequestError.httpError(let statusCode, let message) {
            return UsageSnapshot.failure(
                state: .requestFailed,
                subtitle: "Usage API returned HTTP \(statusCode)",
                errorMessage: message,
                httpStatusCode: statusCode
            )
        } catch {
            return UsageSnapshot.failure(
                state: .requestFailed,
                subtitle: "Usage request failed",
                errorMessage: error.localizedDescription
            )
        }
    }

    private func fetchUsage(accessToken: String) async throws -> UsageSnapshot {
        let (data, httpResponse) = try await fetchJSON(
            from: AppConfiguration.usageEndpoint,
            accessToken: accessToken
        )

        switch httpResponse.statusCode {
        case 200..<300:
            let snapshot = try UsageResponseParser.snapshot(
                from: data,
                fetchedAt: Date(),
                httpStatusCode: httpResponse.statusCode
            ).withResetCredits(
                await fetchResetCredits(accessToken: accessToken)
            )
            UsageSnapshotStore.save(snapshot)
            return snapshot
        case 401, 403:
            throw UsageRequestError.unauthorized(httpResponse.statusCode)
        default:
            throw UsageRequestError.httpError(
                httpResponse.statusCode,
                String(data: data, encoding: .utf8)
            )
        }
    }

    private func fetchResetCredits(accessToken: String) async -> [UsageMetric] {
        do {
            let (data, httpResponse) = try await fetchJSON(
                from: AppConfiguration.resetCreditsEndpoint,
                accessToken: accessToken
            )

            switch httpResponse.statusCode {
            case 200..<300:
                return try UsageResponseParser.resetCreditMetrics(from: data)
            case 401, 403:
                return [
                    UsageMetric(label: "重置次数", value: "登录失效", detail: "HTTP \(httpResponse.statusCode)")
                ]
            default:
                return [
                    UsageMetric(label: "重置次数", value: "不可用", detail: "HTTP \(httpResponse.statusCode)")
                ]
            }
        } catch {
            return [
                UsageMetric(label: "重置次数", value: "不可用", detail: error.localizedDescription)
            ]
        }
    }

    private func fetchJSON(
        from endpoint: URL,
        accessToken: String
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("agent-board-macos-widget", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageRequestError.invalidResponse
        }

        return (data, httpResponse)
    }
}

enum UsageRequestError: Error {
    case invalidResponse
    case unauthorized(Int)
    case httpError(Int, String?)
}
