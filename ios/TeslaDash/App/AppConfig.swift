import Foundation

/// App-level configuration. The backend WebSocket URL lives here (it is not a
/// secret). It defaults to a local backend. For your own deployment, override
/// it in Settings (e.g. ws://localhost:8080/stream, ws://192.168.1.20:8080/stream
/// from a real device on your LAN, or your wss://<host>/stream cloud endpoint).
enum AppConfig {
    /// Default backend stream URL. Overridable at runtime in Settings.
    static let defaultStreamURL = "ws://localhost:8080/stream"

    /// UserDefaults key for a user-overridden backend URL.
    static let streamURLKey = "stream_url"

    /// UserDefaults key for the bearer token guarding the /stream WebSocket.
    /// Retrieve the value with `terraform output -raw stream_token`.
    static let streamTokenKey = "stream_token"

    static var streamURL: URL {
        let stored = UserDefaults.standard.string(forKey: streamURLKey)
        let raw = (stored?.isEmpty == false ? stored! : defaultStreamURL)
        return URL(string: raw) ?? URL(string: defaultStreamURL)!
    }

    /// Bearer token sent on the WebSocket handshake. Empty when unset (local dev
    /// against an open backend).
    static var streamToken: String {
        UserDefaults.standard.string(forKey: streamTokenKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
