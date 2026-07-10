// LibreLinkUp follower API client (specs/data/cgm-connect Req 3).
//
// Implements the contract confirmed by the task 7 spike
// (docs/agent-notes/librelinkup-api.md): login with region redirect,
// bearer + SHA-256 `account-id` header on authenticated calls, connections
// and graph endpoints, mg/dL-only value consumption. All URLSession use in
// the module is confined to this file and its owning source (Req 3.5, 7.1);
// nothing here is reachable from the estimation targets.
import CryptoKit
import Foundation
import Security

// MARK: - Errors

enum LibreLinkUpError: Error, Equatable {
    case noCredentials
    case pendingAccountStep  // login status == 4 (tou / pp / verifyEmail)
    case clientVersionTooOld  // status 920 / HTTP 403 minimumVersion
    case unauthorised  // HTTP 401 — one re-login retry, then failed
    case loginRejected
    case noPatients
    case malformedResponse
    case httpFailure(Int)
    case keychainFailure(OSStatus)
}

// MARK: - Credentials and session

struct LibreLinkUpCredentials: Codable, Sendable, Equatable {
    let email: String
    let password: String
}

// Resolved auth state persisted between fetches: the regional host, the
// bearer token (~6-month validity) and the SHA-256 hex of the user id sent
// as the `account-id` header. Lives in the Keychain beside the credentials.
struct LibreLinkUpSession: Codable, Sendable, Equatable {
    let host: String
    let token: String
    let expires: Date?
    let accountIDHash: String
}

// MARK: - Response payloads (decode-only)

struct LLULoginResponse: Decodable {
    let status: Int
    let data: Payload?

    struct Payload: Decodable {
        let redirect: Bool?
        let region: String?
        let authTicket: AuthTicket?
        let user: User?

        struct AuthTicket: Decodable {
            let token: String
            let expires: Double?  // Unix seconds
        }
        struct User: Decodable {
            let id: String
        }
    }
}

struct LLUConnectionsResponse: Decodable {
    let status: Int
    let data: [Patient]?

    struct Patient: Decodable {
        let patientId: String
    }
}

struct LLUGraphResponse: Decodable {
    let status: Int
    let data: Payload?

    struct Payload: Decodable {
        let connection: Connection?
        let graphData: [LLUMeasurement]?

        struct Connection: Decodable {
            let glucoseMeasurement: LLUMeasurement?
        }
    }
}

// One reading. Only `ValueInMgPerDl` is consumed (converted in-app,
// Req 5.5) — the `Value`/`GlucoseUnits` display pair is deliberately
// ignored, sidestepping the undocumented unit-flag mapping.
struct LLUMeasurement: Decodable {
    let factoryTimestamp: String
    let valueInMgPerDl: Double

    enum CodingKeys: String, CodingKey {
        case factoryTimestamp = "FactoryTimestamp"
        case valueInMgPerDl = "ValueInMgPerDl"
    }
}

// MARK: - Client

final class LibreLinkUpClient: Sendable {

    // Abbott bumps the version floor roughly yearly; the failure is
    // self-describing (status 920 with the advertised minimum). Keep these
    // easy to change.
    static let productHeader = "llu.ios"
    static let versionHeader = "4.16.0"
    static let defaultHost = "https://api-eu.libreview.io"
    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: Auth (Req 3.1 flow; agent-note "Auth flow")

    // Login, following at most one region redirect (status 0 +
    // data.redirect → retry at api-{region}.libreview.io). The returned
    // session carries the RESOLVED host — persist it so later fetches skip
    // the redirect hop.
    func login(
        _ credentials: LibreLinkUpCredentials, host: String
    ) async throws -> LibreLinkUpSession {
        var resolvedHost = host
        for _ in 0..<2 {
            var request = try Self.request(host: resolvedHost, path: "/llu/auth/login")
            request.httpMethod = "POST"
            request.httpBody = try JSONEncoder().encode(credentials)
            let response: LLULoginResponse = try await send(request)

            switch response.status {
            case 4:
                throw LibreLinkUpError.pendingAccountStep
            case 920:
                throw LibreLinkUpError.clientVersionTooOld
            case 0:
                break
            default:
                throw LibreLinkUpError.loginRejected
            }
            guard let payload = response.data else {
                throw LibreLinkUpError.malformedResponse
            }
            if payload.redirect == true, let region = payload.region {
                resolvedHost = "https://api-\(region).libreview.io"
                continue
            }
            guard let ticket = payload.authTicket, let user = payload.user else {
                throw LibreLinkUpError.malformedResponse
            }
            return LibreLinkUpSession(
                host: resolvedHost,
                token: ticket.token,
                expires: ticket.expires.map { Date(timeIntervalSince1970: $0) },
                accountIDHash: Self.sha256Hex(user.id))
        }
        throw LibreLinkUpError.malformedResponse  // redirect loop
    }

    // MARK: Fetch (agent-note "Fetching readings")

    func connections(session: LibreLinkUpSession) async throws -> [LLUConnectionsResponse.Patient] {
        let request = try Self.authenticatedRequest(session: session, path: "/llu/connections")
        let response: LLUConnectionsResponse = try await send(request)
        if response.status == 920 { throw LibreLinkUpError.clientVersionTooOld }
        guard response.status == 0, let patients = response.data else {
            throw LibreLinkUpError.malformedResponse
        }
        return patients
    }

    func graph(session: LibreLinkUpSession, patientID: String) async throws -> LLUGraphResponse {
        let request = try Self.authenticatedRequest(
            session: session, path: "/llu/connections/\(patientID)/graph")
        let response: LLUGraphResponse = try await send(request)
        if response.status == 920 { throw LibreLinkUpError.clientVersionTooOld }
        guard response.status == 0 else { throw LibreLinkUpError.malformedResponse }
        return response
    }

    // MARK: Mapping (pure; unit-tested against canned fixtures)

    // Readings = data.graphData[] plus the latest
    // data.connection.glucoseMeasurement, de-duplicated on FactoryTimestamp
    // — the API has no stable per-reading id, so the sensor-derived
    // FactoryTimestamp string is the nativeID (agent-note "Fetching
    // readings"). Unparseable timestamps are skipped rather than guessed.
    static func samples(from graph: LLUGraphResponse) -> [GlucoseSample] {
        var measurements = graph.data?.graphData ?? []
        if let latest = graph.data?.connection?.glucoseMeasurement {
            measurements.append(latest)
        }
        let formatter = makeFactoryTimestampFormatter()
        var seen: Set<String> = []
        var samples: [GlucoseSample] = []
        for measurement in measurements {
            guard seen.insert(measurement.factoryTimestamp).inserted,
                let instant = formatter.date(from: measurement.factoryTimestamp)
            else { continue }
            samples.append(
                GlucoseSample(
                    nativeInstant: instant,
                    mgPerDl: measurement.valueInMgPerDl,
                    nativeID: measurement.factoryTimestamp))
        }
        return samples
    }

    // FactoryTimestamp is UTC, "M/d/yyyy h:mm:ss a" — parse with
    // en_US_POSIX and the TZ pinned to UTC. Built per call: DateFormatter is
    // not Sendable, and one allocation per 15-minute fetch is negligible.
    static func makeFactoryTimestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy h:mm:ss a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }

    // `account-id` header value: SHA-256 hex of data.user.id (enforced by
    // the API since LLU 4.11).
    static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: Transport

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LibreLinkUpError.malformedResponse
        }
        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw LibreLinkUpError.unauthorised
        case 403:
            // Version-floor rejection arrives as HTTP 403 with
            // {"data":{"minimumVersion":…},"status":920}.
            if Self.envelopeStatus(data) == 920 {
                throw LibreLinkUpError.clientVersionTooOld
            }
            throw LibreLinkUpError.httpFailure(http.statusCode)
        default:
            // 429 Retry-After is deliberately ignored: the 15-minute poll sits
            // far above the API's rate limits (docs/agent-notes/librelinkup-api.md).
            throw LibreLinkUpError.httpFailure(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw LibreLinkUpError.malformedResponse
        }
    }

    private static func envelopeStatus(_ data: Data) -> Int? {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["status"] as? Int
    }

    private static func request(host: String, path: String) throws -> URLRequest {
        guard let url = URL(string: host + path) else {
            throw LibreLinkUpError.malformedResponse
        }
        var request = URLRequest(url: url)
        request.setValue(productHeader, forHTTPHeaderField: "product")
        request.setValue(versionHeader, forHTTPHeaderField: "version")
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func authenticatedRequest(
        session: LibreLinkUpSession, path: String
    ) throws -> URLRequest {
        var request = try request(host: session.host, path: path)
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        request.setValue(session.accountIDHash, forHTTPHeaderField: "account-id")
        return request
    }
}

// MARK: - Keychain storage (Req 3.1)

// Generic-password storage for the credentials and the auth session, with
// kSecAttrAccessibleAfterFirstUnlock so a background refresh on a locked
// device can read them (prerequisites.md). Credentials never appear in
// event metadata; disconnect() wipes both items (Req 6.2).
struct LibreLinkUpKeychain: Sendable {

    private static let service = "com.medata.librelinkup"
    private static let credentialsAccount = "credentials"
    private static let sessionAccount = "session"

    func saveCredentials(_ credentials: LibreLinkUpCredentials) throws {
        try save(try JSONEncoder().encode(credentials), account: Self.credentialsAccount)
    }

    func credentials() -> LibreLinkUpCredentials? {
        read(account: Self.credentialsAccount)
            .flatMap { try? JSONDecoder().decode(LibreLinkUpCredentials.self, from: $0) }
    }

    func saveSession(_ session: LibreLinkUpSession) {
        if let data = try? JSONEncoder().encode(session) {
            try? save(data, account: Self.sessionAccount)
        }
    }

    func session() -> LibreLinkUpSession? {
        read(account: Self.sessionAccount)
            .flatMap { try? JSONDecoder().decode(LibreLinkUpSession.self, from: $0) }
    }

    func deleteSession() {
        delete(account: Self.sessionAccount)
    }

    func deleteAll() {
        delete(account: Self.credentialsAccount)
        delete(account: Self.sessionAccount)
    }

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
    }

    private func save(_ data: Data, account: String) throws {
        SecItemDelete(query(account: account) as CFDictionary)
        var attributes = query(account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LibreLinkUpError.keychainFailure(status)
        }
    }

    private func read(account: String) -> Data? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private func delete(account: String) {
        SecItemDelete(query(account: account) as CFDictionary)
    }
}
