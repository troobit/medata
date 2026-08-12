// LibreLinkUp follower API client (specs/data/cgm-connect Req 3).
//
// Implements the contract confirmed by the task 7 spike
// (docs/agent-notes/librelinkup-api.md): login with region redirect,
// bearer + SHA-256 `account-id` header on authenticated calls, connections
// and graph endpoints, mg/dL-only value consumption.
//
// Extracted from `GlucoseIngestion` into this Foundation-only target so the
// MeDataWidgets extension can fetch for itself while the app is suspended
// (glucose-lock-widget Decision 16) without linking GRDB/Persistence — the
// Decision 12 constraint on the appex link closure still stands. Nothing here
// is reachable from the estimation targets.
import CryptoKit
import Foundation
import Security

// MARK: - Errors

public enum LibreLinkUpError: Error, Equatable {
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

public struct LibreLinkUpCredentials: Codable, Sendable, Equatable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

// Resolved auth state persisted between fetches: the regional host, the
// bearer token (~6-month validity) and the SHA-256 hex of the user id sent
// as the `account-id` header. Lives in the Keychain beside the credentials.
public struct LibreLinkUpSession: Codable, Sendable, Equatable {
    public let host: String
    public let token: String
    public let expires: Date?
    public let accountIDHash: String

    public init(host: String, token: String, expires: Date?, accountIDHash: String) {
        self.host = host
        self.token = token
        self.expires = expires
        self.accountIDHash = accountIDHash
    }

    // A session with no expiry never goes stale on its own; otherwise the
    // stored expiry decides. Both the app's poll loop and the widget's
    // extension-side fetch gate on this before spending a request.
    public func isUsable(at now: Date = Date()) -> Bool {
        guard let expires else { return true }
        return expires > now
    }
}

// MARK: - Response payloads (decode-only)

public struct LLULoginResponse: Decodable {
    public let status: Int
    public let data: Payload?

    public struct Payload: Decodable {
        public let redirect: Bool?
        public let region: String?
        public let authTicket: AuthTicket?
        public let user: User?

        public struct AuthTicket: Decodable {
            public let token: String
            public let expires: Double?  // Unix seconds
        }
        public struct User: Decodable {
            public let id: String
        }
    }
}

public struct LLUConnectionsResponse: Decodable {
    public let status: Int
    public let data: [Patient]?

    public struct Patient: Decodable {
        public let patientId: String
    }
}

public struct LLUGraphResponse: Decodable {
    public let status: Int
    public let data: Payload?

    public struct Payload: Decodable {
        public let connection: Connection?
        public let graphData: [LLUMeasurement]?

        public struct Connection: Decodable {
            public let glucoseMeasurement: LLUMeasurement?
        }
    }
}

// One reading. Only `ValueInMgPerDl` is consumed (converted by the caller,
// Req 5.5) — the `Value`/`GlucoseUnits` display pair is deliberately
// ignored, sidestepping the undocumented unit-flag mapping.
public struct LLUMeasurement: Decodable {
    public let factoryTimestamp: String
    public let valueInMgPerDl: Double

    enum CodingKeys: String, CodingKey {
        case factoryTimestamp = "FactoryTimestamp"
        case valueInMgPerDl = "ValueInMgPerDl"
    }
}

// MARK: - Mapped reading

// One vendor reading, still in the vendor's unit and still un-snapped. The
// deliberately narrow hand-off type between this module and its two consumers:
// `GlucoseIngestion` turns it into a `GlucoseSample` for the ingest path, the
// widget turns it into a `GlucoseReading` for the snapshot derivation. Neither
// unit conversion nor grid snapping happens here — both callers must apply the
// same shared helpers so the two surfaces cannot disagree.
public struct LibreLinkUpReading: Sendable, Equatable {
    public let instant: Date
    public let mgPerDl: Double
    public let nativeID: String

    public init(instant: Date, mgPerDl: Double, nativeID: String) {
        self.instant = instant
        self.mgPerDl = mgPerDl
        self.nativeID = nativeID
    }
}

// MARK: - Client

public final class LibreLinkUpClient: Sendable {

    // Abbott bumps the version floor roughly yearly; the failure is
    // self-describing (status 920 with the advertised minimum). Keep these
    // easy to change.
    public static let productHeader = "llu.ios"
    public static let versionHeader = "4.16.0"
    public static let defaultHost = "https://api-eu.libreview.io"
    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: Auth (Req 3.1 flow; agent-note "Auth flow")

    // Login, following at most one region redirect (status 0 +
    // data.redirect → retry at api-{region}.libreview.io). The returned
    // session carries the RESOLVED host — persist it so later fetches skip
    // the redirect hop.
    //
    // App-side only: the widget never logs in (Decision 16). On a 401 it falls
    // back to the stored snapshot and leaves auth repair to the app's next
    // poll, which removes the two-process re-login race on the shared session.
    public func login(
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

    public func connections(
        session: LibreLinkUpSession
    ) async throws -> [LLUConnectionsResponse.Patient] {
        let request = try Self.authenticatedRequest(session: session, path: "/llu/connections")
        let response: LLUConnectionsResponse = try await send(request)
        if response.status == 920 { throw LibreLinkUpError.clientVersionTooOld }
        guard response.status == 0, let patients = response.data else {
            throw LibreLinkUpError.malformedResponse
        }
        return patients
    }

    public func graph(
        session: LibreLinkUpSession, patientID: String
    ) async throws -> LLUGraphResponse {
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
    public static func readings(from graph: LLUGraphResponse) -> [LibreLinkUpReading] {
        var measurements = graph.data?.graphData ?? []
        if let latest = graph.data?.connection?.glucoseMeasurement {
            measurements.append(latest)
        }
        let formatter = makeFactoryTimestampFormatter()
        var seen: Set<String> = []
        var readings: [LibreLinkUpReading] = []
        for measurement in measurements {
            guard seen.insert(measurement.factoryTimestamp).inserted,
                let instant = formatter.date(from: measurement.factoryTimestamp)
            else { continue }
            readings.append(
                LibreLinkUpReading(
                    instant: instant,
                    mgPerDl: measurement.valueInMgPerDl,
                    nativeID: measurement.factoryTimestamp))
        }
        return readings
    }

    // FactoryTimestamp is UTC, "M/d/yyyy h:mm:ss a" — parse with
    // en_US_POSIX and the TZ pinned to UTC. Built per call: DateFormatter is
    // not Sendable, and one allocation per fetch is negligible.
    public static func makeFactoryTimestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy h:mm:ss a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }

    // `account-id` header value: SHA-256 hex of data.user.id (enforced by
    // the API since LLU 4.11).
    public static func sha256Hex(_ value: String) -> String {
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
            // 429 Retry-After is deliberately ignored: the shared poll gate
            // (LibreLinkUpPolling) holds the combined app+widget rate to one
            // fetch per interval. A 429 or a status-920 churn IS the rollback
            // signal for cgm-connect Decision 13 — it is read from the logs,
            // not handled here.
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
