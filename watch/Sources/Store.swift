import Foundation
import Security

/// The pairing token, in the watch's keychain rather than its preferences.
enum Keychain {
    private static let service = "openGym"
    private static let account = "token"

    static func read() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// The watch's connection to its openGym server and what it last read from it.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var server: String
    @Published private(set) var userName: String?
    @Published private(set) var paired: Bool
    @Published private(set) var summary: WatchSummary?
    @Published private(set) var error: String?
    @Published private(set) var updated: Date?

    /// `-demo` (the screenshots, the simulator): sample data, no server.
    let demo = ProcessInfo.processInfo.arguments.contains("-demo")
    private var polling: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    init() {
        server = defaults.string(forKey: "server") ?? ""
        userName = defaults.string(forKey: "userName")
        paired = Keychain.read() != nil
        if demo {
            paired = true
            userName = "Demo"
            summary = .demo
            updated = Date()
        }
    }

    func pair(server text: String, code: String) async -> Bool {
        error = nil
        guard let url = API.serverURL(text) else { error = APIError.badServer.localizedDescription; return false }
        do {
            let p = try await API.redeem(server: url, code: code)
            Keychain.write(p.token)
            server = url.absoluteString
            userName = p.user?.name
            defaults.set(server, forKey: "server")
            defaults.set(userName, forKey: "userName")
            paired = true
            await refresh()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func unpair() {
        Keychain.write(nil)
        defaults.removeObject(forKey: "userName")
        paired = false
        summary = nil
        userName = nil
        stopPolling()
    }

    func refresh() async {
        if demo { return }
        guard let url = API.serverURL(server), let token = Keychain.read() else { return }
        do {
            summary = try await API.summary(server: url, token: token)
            updated = Date()
            error = nil
        } catch APIError.signedOut {
            unpair()
            error = APIError.signedOut.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// While the app is on screen: every 10 seconds during a workout, every minute otherwise.
    func startPolling() {
        guard polling == nil, !demo else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let busy = await MainActor.run { self?.summary?.active != nil }
                try? await Task.sleep(nanoseconds: (busy ? 10 : 60) * 1_000_000_000)
            }
        }
    }

    func stopPolling() {
        polling?.cancel()
        polling = nil
    }
}

/// Numbers as the app writes them: 60, 22.5, 7 578.
enum Fmt {
    static func num(_ v: Double, decimals: Int = 1) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = decimals
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    static func set(_ s: WatchSummary.WorkSet, unit: String) -> String {
        if let w = s.w, let r = s.r { return "\(num(w)) \(unit) × \(num(r, decimals: 0))" }
        if let r = s.r { return "× \(num(r, decimals: 0))" }
        if let m = s.min { return "\(num(m)) min" }
        if let sec = s.s { return "\(num(sec, decimals: 0)) s" }
        if let w = s.w { return "\(num(w)) \(unit)" }
        return "—"
    }

    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
