import Foundation

/// What the server's `GET /api/watch` answers (api/watch.js): the workout in progress, the last
/// one and the body weight, in a few kilobytes.
struct WatchSummary: Decodable {
    var unit: String
    var restSec: Double
    var active: Active?
    var last: Last?
    var weight: Weight?

    struct Active: Decodable {
        var name: String
        var start: Double?
        var current: Int
        var entries: [Entry]
    }
    struct Entry: Decodable {
        var id: String
        var name: String
        var sets: [WorkSet]
    }
    struct WorkSet: Decodable {
        var done: Bool
        var w: Double?
        var r: Double?
        var min: Double?
        var s: Double?
    }
    struct Last: Decodable {
        var name: String
        var d: String
        var vol: Double?
        var sets: Int
    }
    struct Weight: Decodable {
        var d: String
        var w: Double
    }
}

enum APIError: LocalizedError {
    case badServer, invalidCode, signedOut, unreachable, http(Int)

    var errorDescription: String? {
        switch self {
        case .badServer: return String(localized: "That is not a server address.")
        case .invalidCode: return String(localized: "The code is wrong or has expired. Make a new one.")
        case .signedOut: return String(localized: "The watch was signed out. Pair it again.")
        case .unreachable: return String(localized: "The server could not be reached.")
        case .http(let code): return String(localized: "The server answered \(code).")
        }
    }
}

/// The two calls the watch makes: redeeming a pairing code for a token (as the phone app does,
/// `POST /api/pair/redeem`), and reading the summary with that token.
enum API {
    /// "gym.example.com" or "https://gym.example.com/" → https://gym.example.com
    static func serverURL(_ text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    private static func send(_ req: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, res) = try await session.data(for: req)
            return (data, (res as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw APIError.unreachable
        }
    }

    struct Paired: Decodable {
        struct User: Decodable { var name: String? }
        var token: String
        var user: User?
    }

    static func redeem(server: URL, code: String) async throws -> Paired {
        var req = URLRequest(url: server.appendingPathComponent("api/pair/redeem"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["code": code.trimmingCharacters(in: .whitespaces).uppercased()])
        let (data, status) = try await send(req)
        if status == 400 { throw APIError.invalidCode }
        guard status == 200 else { throw APIError.http(status) }
        return try JSONDecoder().decode(Paired.self, from: data)
    }

    static func summary(server: URL, token: String) async throws -> WatchSummary {
        var req = URLRequest(url: server.appendingPathComponent("api/watch"))
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, status) = try await send(req)
        if status == 401 { throw APIError.signedOut }
        guard status == 200 else { throw APIError.http(status) }
        return try JSONDecoder().decode(WatchSummary.self, from: data)
    }
}

extension WatchSummary {
    /// What the screenshots and the simulator show with `-demo`, with no server.
    static let demo = WatchSummary(
        unit: "kg", restSec: 90,
        active: Active(name: "Push", start: Date().addingTimeInterval(-1500).timeIntervalSince1970 * 1000, current: 1, entries: [
            Entry(id: "1", name: "Bench Press", sets: [WorkSet(done: true, w: 60, r: 8), WorkSet(done: true, w: 60, r: 8), WorkSet(done: true, w: 60, r: 7)]),
            Entry(id: "2", name: "Seated Shoulder Press", sets: [WorkSet(done: true, w: 22.5, r: 10), WorkSet(done: false, w: 22.5, r: 10), WorkSet(done: false, w: 22.5, r: 10)]),
            Entry(id: "3", name: "Triceps Pushdown", sets: [WorkSet(done: false, w: 25, r: 12), WorkSet(done: false, w: 25, r: 12)]),
        ]),
        last: Last(name: "Legs", d: "2026-10-18", vol: 7578, sets: 18),
        weight: Weight(d: "2026-10-20", w: 71.7)
    )
}
